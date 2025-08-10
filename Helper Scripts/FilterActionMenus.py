#!/usr/bin/env python3
import os
import re

truffle_dir = "/Applications/Chocolat.app/Contents/SharedSupport/Truffles"

def tokenize(text):
    """Tokenize S-expression text"""
    tokens = []
    current = ''
    in_brackets = False
    
    for char in text:
        if char == '[':
            if current:
                tokens.append(current)
                current = ''
            in_brackets = True
            current = '['
        elif char == ']':
            if in_brackets:
                current += ']'
                tokens.append(current)
                current = ''
                in_brackets = False
        elif char in '()' and not in_brackets:
            if current:
                tokens.append(current)
                current = ''
            tokens.append(char)
        elif char in ' \t\n' and not in_brackets:
            if current:
                tokens.append(current)
                current = ''
        else:
            current += char
    
    if current:
        tokens.append(current)
    
    return tokens

def parse(tokens):
    """Parse tokens into nested structure"""
    if not tokens:
        return None
    
    token = tokens.pop(0)
    
    if token == '(':
        lst = []
        while tokens and tokens[0] != ')':
            elem = parse(tokens)
            if elem is not None:
                lst.append(elem)
        if tokens:
            tokens.pop(0)  # Remove closing ')'
        return lst
    elif token == ')':
        return None
    else:
        return token

def is_snippet(item):
    """Check if item is a snippet reference"""
    if isinstance(item, str):
        # Direct snippet reference
        if item.startswith('snippet.'):
            return True
        # Bracketed snippet reference
        if item.startswith('[') and item.endswith(']'):
            inner = item[1:-1]
            if inner.startswith('snippet.'):
                return True
    return False

def clean_separators_in_list(items):
    """Remove leading, trailing, and consecutive separators from a list"""
    if not items:
        return items
    
    # Remove leading separators
    while items and items[0] == '---':
        items = items[1:]
    
    # Remove trailing separators
    while items and items[-1] == '---':
        items = items[:-1]
    
    # Remove consecutive separators
    cleaned = []
    prev_was_separator = False
    for item in items:
        if item == '---':
            if not prev_was_separator:
                cleaned.append(item)
            prev_was_separator = True
        else:
            cleaned.append(item)
            prev_was_separator = False
    
    return cleaned

def filter_sexp(sexp):
    """Filter S-expression to keep only snippets"""
    if not isinstance(sexp, list):
        return sexp if (is_snippet(sexp) or sexp == '---') else None
    
    if not sexp:
        return None
    
    # Check what kind of list this is
    first = sexp[0]
    
    if first == 'menu':
        # Filter menu items
        filtered = ['menu']
        for item in sexp[1:]:
            filtered_item = filter_sexp(item)
            if filtered_item is not None:
                filtered.append(filtered_item)
        
        # Flatten single-child submenus
        flattened = flatten_single_children(filtered)
        # Handle case where entire menu might have been flattened
        if isinstance(flattened, list):
            filtered = flattened
        else:
            filtered = ['menu', flattened]
        
        # Clean up separators in menu items
        menu_items = filtered[1:]
        menu_items = clean_separators_in_list(menu_items)
        
        return ['menu'] + menu_items if menu_items else ['menu']
    
    elif first == 'submenu':
        if len(sexp) < 2:
            return None
        
        # Get submenu name
        name = sexp[1]
        
        # Filter submenu items
        filtered = ['submenu', name]
        has_content = False
        
        for item in sexp[2:]:
            filtered_item = filter_sexp(item)
            if filtered_item is not None:
                filtered.append(filtered_item)
                if filtered_item != '---':
                    has_content = True
        
        # Flatten single-child submenus within this submenu
        flattened = flatten_single_children(filtered)
        # If this submenu was completely flattened, return just the item
        if not isinstance(flattened, list) or (isinstance(flattened, list) and len(flattened) > 0 and flattened[0] != 'submenu'):
            return flattened
        filtered = flattened
        
        # Clean up separators in submenu items
        if len(filtered) > 2:
            submenu_items = filtered[2:]
            submenu_items = clean_separators_in_list(submenu_items)
            filtered = ['submenu', name] + submenu_items
            has_content = any(item != '---' for item in submenu_items)
        
        # Only return submenu if it has actual content (not just separators)
        return filtered if has_content else None
    
    else:
        # It's a list of items, filter each
        filtered = []
        for item in sexp:
            filtered_item = filter_sexp(item)
            if filtered_item is not None:
                filtered.append(filtered_item)
        return filtered if filtered else None

def flatten_single_children(sexp):
    """Flatten single-child submenus"""
    if not isinstance(sexp, list) or len(sexp) < 2:
        return sexp
    
    first = sexp[0]
    if first not in ['menu', 'submenu']:
        return sexp
    
    # Get the items (skip 'menu' or 'submenu name')
    if first == 'submenu':
        name = sexp[1]
        items = sexp[2:]
    else:
        name = None
        items = sexp[1:]
    
    # First recursively flatten any child submenus
    processed_items = []
    for item in items:
        if isinstance(item, list) and len(item) > 0 and item[0] == 'submenu':
            flattened = flatten_single_children(item)
            # If the child submenu was flattened to a single item, add just that item
            if isinstance(flattened, str) or (isinstance(flattened, list) and flattened[0] != 'submenu'):
                processed_items.append(flattened)
            else:
                processed_items.append(flattened)
        else:
            processed_items.append(item)
    
    # Now check if we have only one child (ignoring separators)
    non_separator_items = [x for x in processed_items if x != '---']
    
    # Special handling for different cases
    if len(non_separator_items) == 1:
        single_item = non_separator_items[0]
        
        # If we're a menu and have a single submenu, pull up its contents
        if first == 'menu' and isinstance(single_item, list) and single_item[0] == 'submenu':
            # Extract the submenu's items and return them directly in the menu
            submenu_items = single_item[2:]  # Skip 'submenu' and name
            return ['menu'] + submenu_items
        
        # If we're a submenu with a single item (not a submenu), flatten
        elif first == 'submenu':
            # If the single item is another submenu, this was already handled above
            if not (isinstance(single_item, list) and single_item[0] == 'submenu'):
                # Single non-submenu item, return it to be incorporated by parent
                return single_item
    
    # Otherwise, return the normal structure
    result = [first]
    if name:
        result.append(name)
    result.extend(processed_items)
    
    return result

def serialize(sexp, indent=0):
    """Convert filtered S-expression back to string"""
    if sexp is None:
        return ''
    
    if isinstance(sexp, str):
        return sexp
    
    if isinstance(sexp, list):
        if not sexp:
            return '()'
        
        first = sexp[0]
        
        if first == 'menu':
            result = '(menu'
            for item in sexp[1:]:
                if isinstance(item, list):
                    result += '\n    ' + serialize(item, indent + 1)
                else:
                    result += ' ' + serialize(item, indent)
            result += ')'
            return result
        
        elif first == 'submenu':
            if len(sexp) < 2:
                return ''
            
            # Check if all items fit on one line
            all_simple = all(not isinstance(item, list) for item in sexp[2:])
            
            if all_simple and len(sexp) <= 6:  # Short submenu, one line
                result = '    ' * indent + '(submenu ' + sexp[1]
                for item in sexp[2:]:
                    result += ' ' + serialize(item, indent)
                result += ')'
            else:  # Multi-line submenu
                result = '    ' * indent + '(submenu ' + sexp[1]
                for item in sexp[2:]:
                    if isinstance(item, list):
                        result += '\n' + serialize(item, indent + 1)
                    else:
                        result += ' ' + serialize(item, indent)
                if not all_simple:
                    result += ')'
                else:
                    result += ')'
            return result
        
        else:
            # Regular list of items
            return ' '.join(serialize(item, indent) for item in sexp)
    
    return str(sexp)


def filter_menu_file(filepath):
    """Filter a menu.selfml file"""
    with open(filepath, 'r') as f:
        content = f.read()
    
    if not content.strip():
        return False
    
    try:
        # Parse the file
        tokens = tokenize(content)
        parsed = parse(tokens)
        
        # Filter to keep only snippets
        filtered = filter_sexp(parsed)
        
        # Serialize back
        if filtered:
            result = serialize(filtered)
        else:
            result = '(menu)'
        
        # Only write if changed
        if result != content:
            with open(filepath, 'w') as f:
                f.write(result)
            return True
            
    except Exception as e:
        print(f"    Error: {e}")
        return False
    
    return False

# First restore all files from backup
print("Restoring original files from backup...")
os.system(f"tar -xzf /tmp/truffles_original_backup.tar.gz -C /Applications/Chocolat.app/Contents/SharedSupport")

# Process all menu.selfml files
print("\nFiltering menu files...")
modified_count = 0
for root, dirs, files in os.walk(truffle_dir):
    for file in files:
        if file == "menu.selfml":
            filepath = os.path.join(root, file)
            truffle_name = os.path.basename(os.path.dirname(filepath))
            
            try:
                if filter_menu_file(filepath):
                    print(f"Modified: {truffle_name}")
                    modified_count += 1
            except Exception as e:
                print(f"Error processing {truffle_name}: {e}")

print(f"\nTotal modified: {modified_count} menu files")