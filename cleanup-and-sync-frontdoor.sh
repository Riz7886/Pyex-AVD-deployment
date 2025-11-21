#!/bin/bash

# Cleanup and Sync Front Door Terraform Code
# This script safely removes old Front Door code and adds new clean code

set -e

echo "================================================"
echo "Front Door Terraform Code Cleanup and Sync"
echo "================================================"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    echo -e "${RED}Error: Not in a git repository. Please run from your project root.${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 1: Finding and backing up old Front Door code...${NC}"

# Create backup directory
BACKUP_DIR="backup_frontdoor_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Find and backup old Front Door terraform files
find . -type f \( -name "*frontdoor*.tf" -o -name "*front-door*.tf" -o -name "*fd-*.tf" \) | while read file; do
    if [[ ! "$file" =~ $BACKUP_DIR ]]; then
        echo "  Backing up: $file"
        cp "$file" "$BACKUP_DIR/"
    fi
done

echo -e "${GREEN}Backup created in: $BACKUP_DIR${NC}"

echo -e "${YELLOW}Step 2: Removing old Front Door code...${NC}"

# Remove old Front Door terraform files (not directories)
find . -type f \( -name "*frontdoor*.tf" -o -name "*front-door*.tf" -o -name "*fd-*.tf" \) | while read file; do
    if [[ ! "$file" =~ $BACKUP_DIR ]] && [[ ! "$file" =~ "Pyx-AVD-deployment/DriversHealth-FrontDoor" ]]; then
        echo "  Removing: $file"
        rm -f "$file"
    fi
done

# Remove old Front Door directories (except new one)
find . -type d -name "*frontdoor*" -o -name "*front-door*" | while read dir; do
    if [[ ! "$dir" =~ $BACKUP_DIR ]] && [[ ! "$dir" =~ "Pyx-AVD-deployment/DriversHealth-FrontDoor" ]]; then
        echo "  Removing directory: $dir"
        rm -rf "$dir"
    fi
done

echo -e "${GREEN}Old Front Door code removed${NC}"

echo -e "${YELLOW}Step 3: Creating new Front Door deployment structure...${NC}"

# Create correct directory structure
mkdir -p Pyx-AVD-deployment/DriversHealth-FrontDoor
cd Pyx-AVD-deployment/DriversHealth-FrontDoor

echo -e "${GREEN}Directory structure created${NC}"

echo -e "${YELLOW}Step 4: Git operations...${NC}"

# Stage deletions
git add -A

# Check if there are changes to commit
if git diff-index --quiet HEAD --; then
    echo -e "${YELLOW}No changes to commit${NC}"
else
    # Commit the cleanup
    git commit -m "Clean up old Front Door Terraform code

- Removed old Front Door configurations
- Prepared for new Drivers Health Front Door deployment
- Backup created in $BACKUP_DIR"
    
    echo -e "${GREEN}Changes committed${NC}"
fi

cd ../..

echo -e "${YELLOW}Step 5: Adding new Front Door Terraform files...${NC}"

# New files will be created by Claude in the correct location

echo -e "${GREEN}Ready for new Front Door deployment!${NC}"

echo ""
echo "================================================"
echo "Next Steps:"
echo "================================================"
echo "1. New Terraform files will be created in:"
echo "   Pyx-AVD-deployment/DriversHealth-FrontDoor/"
echo ""
echo "2. Review the new files"
echo ""
echo "3. Initialize and deploy:"
echo "   cd Pyx-AVD-deployment/DriversHealth-FrontDoor"
echo "   terraform init"
echo "   terraform plan"
echo "   terraform apply"
echo ""
echo "4. Sync to Git:"
echo "   git add Pyx-AVD-deployment/DriversHealth-FrontDoor/"
echo "   git commit -m 'Add new Front Door Terraform deployment'"
echo "   git push"
echo ""
echo -e "${GREEN}Cleanup complete! Old code backed up to: $BACKUP_DIR${NC}"
echo "================================================"
