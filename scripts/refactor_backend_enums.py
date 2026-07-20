import os
import re

def process_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    original_content = content

    # Add Enum imports if not present and if file uses them
    needs_listing_status = False
    needs_user_status = False
    needs_category_status = False
    needs_search_alert_status = False

    # SQLAlchemy Filters
    content = re.sub(r'Listing\.is_active\s*==\s*True,\s*Listing\.is_deleted\s*==\s*False', 'Listing.status == ListingStatus.ACTIVE', content)
    content = re.sub(r'Listing\.is_active\.is_\(True\)', 'Listing.status == ListingStatus.ACTIVE', content)
    content = re.sub(r'Listing\.is_active\s*==\s*True', 'Listing.status == ListingStatus.ACTIVE', content)
    content = re.sub(r'Listing\.is_active\s*==\s*False', 'Listing.status == ListingStatus.PASSIVE', content)
    content = re.sub(r'Listing\.is_deleted\s*==\s*True', 'Listing.status == ListingStatus.DELETED', content)
    content = re.sub(r'Listing\.is_deleted\s*==\s*False', 'Listing.status != ListingStatus.DELETED', content)

    content = re.sub(r'User\.is_active\s*==\s*True', 'User.status == UserStatus.ACTIVE', content)
    content = re.sub(r'User\.is_active\s*==\s*False', 'User.status == UserStatus.PASSIVE', content)

    # Raw SQL Replacements
    content = re.sub(r'(l\.|)is_active\s*=\s*TRUE\s*AND\s*(l\.|)is_deleted\s*=\s*FALSE', r"\1status = 'active'", content, flags=re.IGNORECASE)
    content = re.sub(r'(l\.|)is_active\s*=\s*TRUE', r"\1status = 'active'", content, flags=re.IGNORECASE)
    content = re.sub(r'(l\.|)is_active\s*=\s*FALSE', r"\1status = 'passive'", content, flags=re.IGNORECASE)
    content = re.sub(r'(u\.|)is_active\s*=\s*TRUE', r"\1status = 'active'", content, flags=re.IGNORECASE)
    content = re.sub(r'(u\.|)is_active\s*=\s*FALSE', r"\1status = 'passive'", content, flags=re.IGNORECASE)
    
    # COUNT / FILTER SQL
    content = re.sub(r'is_active\s+AND\s+NOT\s+is_deleted', "status = 'active'", content, flags=re.IGNORECASE)
    content = re.sub(r'l\.is_active\s+AND\s+NOT\s+l\.is_deleted', "l.status = 'active'", content, flags=re.IGNORECASE)

    # Instance attribute replacements
    content = re.sub(r'listing\.is_active\s*=\s*True', 'listing.status = ListingStatus.ACTIVE', content)
    content = re.sub(r'listing\.is_active\s*=\s*False', 'listing.status = ListingStatus.PASSIVE', content)
    content = re.sub(r'listing\.is_deleted\s*=\s*True', 'listing.status = ListingStatus.DELETED', content)
    
    content = re.sub(r'user\.is_active\s*=\s*True', 'user.status = UserStatus.ACTIVE', content)
    content = re.sub(r'user\.is_active\s*=\s*False', 'user.status = UserStatus.PASSIVE', content)
    content = re.sub(r'u\.is_active\s*=\s*False', 'u.status = UserStatus.PASSIVE', content)
    
    content = re.sub(r'alert\.is_active\s*=\s*False', 'alert.status = SearchAlertStatus.PASSIVE', content)

    # Boolean Checks
    content = re.sub(r'not\s+listing\.is_active', 'listing.status != ListingStatus.ACTIVE', content)
    content = re.sub(r'listing\.is_active', '(listing.status == ListingStatus.ACTIVE)', content)
    
    content = re.sub(r'not\s+user\.is_active', 'user.status != UserStatus.ACTIVE', content)
    content = re.sub(r'user\.is_active', '(user.status == UserStatus.ACTIVE)', content)

    # Pydantic Schemas / Output
    content = re.sub(r'"is_active":\s*(.*?\.status\s*==\s*.*?ACTIVE.*?),', r'"status": \1.value,', content)
    # Reverting accidental replacements from previous script or handling dictionary mapping
    content = content.replace('\"is_active\": (listing.status == ListingStatus.ACTIVE),', '\"status\": listing.status,')
    content = content.replace('\"is_active\": (l.status == ListingStatus.ACTIVE),', '\"status\": l.status,')
    content = content.replace('\"is_active\": (u.status == UserStatus.ACTIVE),', '\"status\": u.status,')

    # .values(is_active=False) -> .values(status=ListingStatus.PASSIVE)
    content = re.sub(r'\.values\(is_active=False', '.values(status=ListingStatus.PASSIVE', content)
    content = re.sub(r'\.values\(is_active=True', '.values(status=ListingStatus.ACTIVE', content)

    # Check if we need to add imports
    if 'ListingStatus' in content and 'ListingStatus' not in original_content:
        needs_listing_status = True
    if 'UserStatus' in content and 'UserStatus' not in original_content:
        needs_user_status = True
    if 'CategoryStatus' in content and 'CategoryStatus' not in original_content:
        needs_category_status = True
    if 'SearchAlertStatus' in content and 'SearchAlertStatus' not in original_content:
        needs_search_alert_status = True

    imports_to_add = []
    if needs_listing_status: imports_to_add.append('ListingStatus')
    if needs_user_status: imports_to_add.append('UserStatus')
    if needs_category_status: imports_to_add.append('CategoryStatus')
    if needs_search_alert_status: imports_to_add.append('SearchAlertStatus')

    if imports_to_add:
        import_stmt = f"from app.models.enums import {', '.join(imports_to_add)}\n"
        import_match = re.search(r'^from app\.', content, flags=re.MULTILINE)
        if import_match:
            idx = content.find(import_match.group())
            content = content[:idx] + import_stmt + content[idx:]
        else:
            content = import_stmt + content

    if content != original_content:
        with open(filepath, 'w') as f:
            f.write(content)
        print(f"Updated {filepath}")

import glob

for root, dirs, files in os.walk('/Users/tucibeyin/Desktop/teqlif/backend/app'):
    for file in files:
        if file.endswith('.py') and not file.startswith('__') and file not in ('enums.py', 'user.py', 'listing.py', 'search_alert.py', 'category.py'):
            process_file(os.path.join(root, file))

