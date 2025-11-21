# TROUBLESHOOTING GUIDE - PowerShell Script Issues

## 🔴 ERRORS YOU'RE SEEING:

1. **"The term '.\Deploy--secure-nginx-dmz.ps1' is not recognized"**
   - You have TWO dashes (--) in filename but should be ONE dash (-)
   
2. **"char 25, variables reference is not valid"**
   - File encoding issue or corrupted copy/paste

3. **"executable program not found"**
   - Wrong filename or wrong location

---

## ✅ HOW TO FIX - STEP BY STEP

### **OPTION 1: Use the NEW Clean Script (RECOMMENDED)**

1. **Download the NEW clean script:**
   - File: `Deploy-NGINX-Proxy-SECURE.ps1`
   - Location: Check your downloads

2. **Save it to a folder:**
   ```powershell
   # Example: Save to C:\Scripts\
   mkdir C:\Scripts -Force
   # Copy the file to C:\Scripts\
   ```

3. **Open PowerShell as Administrator:**
   - Press Windows key
   - Type "PowerShell"
   - Right-click "Windows PowerShell"
   - Click "Run as Administrator"

4. **Navigate to the folder:**
   ```powershell
   cd C:\Scripts
   ```

5. **Check the file exists:**
   ```powershell
   dir *.ps1
   ```
   You should see: `Deploy-NGINX-Proxy-SECURE.ps1`

6. **Set execution policy (IMPORTANT):**
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
   ```

7. **Run the script:**
   ```powershell
   .\Deploy-NGINX-Proxy-SECURE.ps1
   ```

---

### **OPTION 2: Fix Your Current Script**

If you want to fix the script you already have:

1. **Check the filename (IMPORTANT!):**
   ```powershell
   # In the folder where your script is, run:
   dir *.ps1
   ```
   
   **Look for:**
   - ❌ `Deploy--secure-nginx-dmz.ps1` (TWO dashes - WRONG)
   - ✅ `deploy-secure-nginx-dmz.ps1` (ONE dash - CORRECT)

2. **If you have two dashes, rename it:**
   ```powershell
   # Rename the file to have only ONE dash:
   Rename-Item "Deploy--secure-nginx-dmz.ps1" "deploy-secure-nginx-dmz.ps1"
   ```

3. **Set execution policy:**
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
   ```

4. **Run with correct name:**
   ```powershell
   .\deploy-secure-nginx-dmz.ps1
   ```

---

## 🔍 DIAGNOSTIC COMMANDS

### **Check if Azure CLI is installed:**
```powershell
az --version
```
If this fails, install Azure CLI from:
https://aka.ms/installazurecliwindows

### **Check PowerShell version:**
```powershell
$PSVersionTable.PSVersion
```
You need at least version 5.1

### **Check execution policy:**
```powershell
Get-ExecutionPolicy
```
If it says "Restricted", that's your problem!

### **Check current location:**
```powershell
Get-Location
```
Make sure you're in the right folder!

### **List all files in current folder:**
```powershell
dir
```
Can you see your .ps1 file?

---

## 🚨 COMMON MISTAKES

### **Mistake 1: Wrong Filename**
**What you typed:**
```powershell
.\Deploy--secure-nginx-dmz.ps1
```
**Notice:** TWO dashes (--)

**Correct:**
```powershell
.\deploy-secure-nginx-dmz.ps1
```
**Notice:** ONE dash (-)

---

### **Mistake 2: Wrong Folder**
```powershell
# Check where you are:
Get-Location

# If wrong folder, navigate to correct one:
cd C:\Path\To\Your\Script
```

---

### **Mistake 3: Execution Policy**
```powershell
# Fix with this command:
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

---

## 🆘 STILL NOT WORKING?

### **Try This Quick Test:**

1. **Open PowerShell as Administrator**

2. **Paste and run this test:**
   ```powershell
   # Test 1: Check Azure CLI
   Write-Host "Test 1: Azure CLI" -ForegroundColor Yellow
   az --version
   
   # Test 2: Check Execution Policy
   Write-Host "Test 2: Execution Policy" -ForegroundColor Yellow
   Get-ExecutionPolicy
   
   # Test 3: List files
   Write-Host "Test 3: Files in current folder" -ForegroundColor Yellow
   dir *.ps1
   
   # Test 4: Check PowerShell version
   Write-Host "Test 4: PowerShell Version" -ForegroundColor Yellow
   $PSVersionTable.PSVersion
   ```

3. **Send me the output** and I'll help you fix it!

---

## ✅ CORRECT COMMAND SEQUENCE

Here's the EXACT sequence that should work:

```powershell
# 1. Open PowerShell as ADMINISTRATOR

# 2. Navigate to where you saved the script
cd C:\Scripts

# 3. Check the file is there
dir *.ps1

# 4. Set execution policy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# 5. Run the script (use the EXACT filename you see)
.\Deploy-NGINX-Proxy-SECURE.ps1
```

---

## 📋 PRE-FLIGHT CHECKLIST

Before running the script, make sure:

- ✅ You opened PowerShell as **Administrator**
- ✅ You're in the correct folder (`cd C:\Path\To\Script`)
- ✅ The script file exists (`dir *.ps1`)
- ✅ Execution policy is set (`Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process`)
- ✅ Azure CLI is installed (`az --version`)
- ✅ You're using the correct filename (check for typos!)

---

## 🏢 WORK LAPTOP SPECIFIC ISSUES

If your work laptop blocks the script:

### **Option A: Run from Different Location**
```powershell
# Try from your user profile instead:
cd $env:USERPROFILE\Documents
# Copy script here and run
```

### **Option B: Use Azure Cloud Shell**
If your work laptop is too locked down:
1. Go to https://portal.azure.com
2. Click the Cloud Shell icon (>_) in top right
3. I can give you a Bash version of the script

### **Option C: Ask IT for Permission**
```powershell
# Show your IT department these commands:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## 📞 WHAT TO SEND ME IF STILL BROKEN

If it still doesn't work, send me:

1. **The exact error message** (copy the whole red text)
2. **This command output:**
   ```powershell
   dir *.ps1
   ```
3. **This command output:**
   ```powershell
   Get-ExecutionPolicy
   ```
4. **This command output:**
   ```powershell
   az --version
   ```

Then I can tell you EXACTLY what's wrong!

---

## 🎯 QUICK FIX - TRY THIS FIRST

**If you're lazy and just want it to work NOW:**

1. Open PowerShell as Administrator
2. Run these 3 commands:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
cd $env:USERPROFILE\Downloads
.\Deploy-NGINX-Proxy-SECURE.ps1
```

That should work if the file is in your Downloads folder!
