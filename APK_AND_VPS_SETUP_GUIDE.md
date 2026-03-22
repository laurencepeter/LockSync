# NPUPS — APK Build & VPS/Coolify Setup Guide

---

## PART 1: Building the Android APK

### Prerequisites (one-time setup)

1. **Install Flutter SDK**
   ```bash
   # Download Flutter from https://docs.flutter.dev/get-started/install/linux
   tar xf flutter_linux_*.tar.xz
   export PATH="$PATH:`pwd`/flutter/bin"
   # Add to ~/.bashrc or ~/.zshrc to make permanent
   echo 'export PATH="$PATH:/path/to/flutter/bin"' >> ~/.bashrc
   ```

2. **Install Java Development Kit (JDK 17)**
   ```bash
   sudo apt update
   sudo apt install openjdk-17-jdk
   java -version  # should show 17.x
   ```

3. **Install Android SDK / Command Line Tools**
   ```bash
   # Option A: Install Android Studio (easiest)
   # Download from https://developer.android.com/studio

   # Option B: Command line tools only
   mkdir -p ~/Android/cmdline-tools
   cd ~/Android/cmdline-tools
   # Download cmdline-tools from https://developer.android.com/studio#command-tools
   unzip commandlinetools-linux-*.zip
   mv cmdline-tools latest
   export ANDROID_HOME=~/Android
   export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"
   ```

4. **Install required Android SDK packages**
   ```bash
   sdkmanager --install "platform-tools" "platforms;android-34" "build-tools;34.0.0"
   sdkmanager --licenses   # Accept all licenses
   ```

5. **Verify Flutter setup**
   ```bash
   flutter doctor
   # All items should show green checkmarks (or at least Android toolchain ✓)
   ```

---

### Step-by-Step: Build the APK

**Step 1 — Clone the repo and navigate to project**
```bash
git clone https://github.com/laurencepeter/LockSync.git
cd LockSync
```

**Step 2 — Install Flutter dependencies**
```bash
flutter pub get
```

**Step 3 — Check for any issues**
```bash
flutter doctor -v
flutter analyze   # Optional: check for code issues
```

**Step 4 — Build the APK**

*Debug APK* (for testing, no signing required):
```bash
flutter build apk --debug
# Output: build/app/outputs/flutter-apk/app-debug.apk
```

*Release APK* (for distribution):
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

*Split APKs by CPU architecture* (smaller file sizes):
```bash
flutter build apk --split-per-abi --release
# Outputs:
#   build/app/outputs/flutter-apk/app-arm64-v8a-release.apk  (modern phones)
#   build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk (older phones)
#   build/app/outputs/flutter-apk/app-x86_64-release.apk      (emulators)
```

> **Recommendation:** Use `app-arm64-v8a-release.apk` for most modern Android phones.

---

### Step 5 — Sign the Release APK (required for Play Store / sideloading)

**Create a keystore (one-time):**
```bash
keytool -genkey -v \
  -keystore ~/npups-keystore.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias npups-key
# You'll be prompted for a password and details — keep the password safe!
```

**Create `android/key.properties`:**
```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=npups-key
storeFile=/home/YOUR_USERNAME/npups-keystore.jks
```

**Update `android/app/build.gradle`** — add signing config:
```groovy
// Add before android { ... }
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    // ... existing config ...

    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}
```

**Build signed release APK:**
```bash
flutter build apk --release
```

---

### Step 6 — Install APK on Device

**Via ADB (USB):**
```bash
# Enable Developer Options + USB Debugging on your Android phone
adb install build/app/outputs/flutter-apk/app-release.apk
```

**Via file transfer:**
- Copy the APK to your phone
- On the phone: Settings → Security → Allow unknown sources
- Tap the APK file to install

---

## PART 2: VPS & Coolify Setup

### VPS Initial Configuration

**Step 1 — Connect to your VPS**
```bash
ssh root@YOUR_VPS_IP
```

**Step 2 — Update the system**
```bash
apt update && apt upgrade -y
```

**Step 3 — Create a non-root user (security best practice)**
```bash
adduser deployer
usermod -aG sudo deployer
# Copy SSH keys
rsync --archive --chown=deployer:deployer ~/.ssh /home/deployer
```

**Step 4 — Configure firewall**
```bash
ufw allow OpenSSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 8000/tcp  # App server (if needed)
ufw enable
ufw status
```

**Step 5 — Install Docker**
```bash
curl -fsSL https://get.docker.com | sh
usermod -aG docker deployer
# Log out and back in for group to take effect
```

**Step 6 — Point your domain to the VPS**
- In your DNS provider: Add an **A record** pointing `yourdomain.com` → `YOUR_VPS_IP`
- Wait for DNS propagation (up to 24h, usually minutes)

---

### Coolify Installation & Configuration

**Step 1 — Install Coolify**
```bash
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
```

**Step 2 — Access the Coolify dashboard**
- Open browser: `http://YOUR_VPS_IP:8000`
- Complete the initial setup wizard (create admin account)

**Step 3 — Add your server**
- Coolify Dashboard → Servers → Add Server
- For the same VPS: choose **localhost**
- Validate the connection

**Step 4 — Connect GitHub (for auto-deploy)**
- Settings → Source → GitHub → Connect
- Install the Coolify GitHub App on your repo
- Grant access to the `LockSync` repository

**Step 5 — Deploy the NPUPS Web App**
1. New Project → New Service → **Docker Compose** (or **Dockerfile**)
2. Source: GitHub → select `laurencepeter/LockSync`
3. Branch: `master` or `main`
4. Dockerfile path: `./Dockerfile`
5. Port: `80`
6. Set environment variables (from `server/.env.example`):
   ```
   JWT_SECRET=your-strong-secret-here
   NODE_ENV=production
   ```
7. Set domain: `yourdomain.com`
8. Enable **Auto SSL** (Let's Encrypt) ✓
9. Click **Deploy**

**Step 6 — Deploy the Backend Server**
1. New Service in the same project
2. Source: GitHub → `LockSync`
3. Dockerfile path: `./server/Dockerfile`
4. Port: `3001` (or whatever the server uses)
5. Set environment variables from `server/.env.example`
6. Deploy

**Step 7 — Enable Auto-Deploy on push**
- Service settings → Auto Deploy → Enable
- This triggers a redeploy every time you push to the branch

---

### Useful Coolify Tips

| Task | Where |
|------|-------|
| View logs | Service → Logs tab |
| Restart a service | Service → Restart button |
| Update environment vars | Service → Environment Variables |
| Check resource usage | Server → Resources |
| Manually trigger deploy | Service → Deploy button |
| Rollback | Service → Deployments → pick previous |

---

### Quick Reference: Common Commands

```bash
# Rebuild and push Docker image manually
docker build -t ghcr.io/laurencepeter/locksync:latest .
docker push ghcr.io/laurencepeter/locksync:latest

# Check running containers on VPS
docker ps

# View container logs
docker logs <container_id> -f

# Restart a container
docker restart <container_id>
```
