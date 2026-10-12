#!/usr/bin/env bash
# ==============================================================================
# Script: setup_kioskmode_opensuse.sh
# Beskrivning: Automatiserat skript för att konfigurera och låsa en openSUSE kiosk-miljö för valfri användare.
# Målsystem: openSUSE (KDE Plasma 6)
# VIKTIGT! Om du får ett felmeddelande, kör: sed -i 's/\r$//' setup_openSUSE_kiosk_v2.4.sh
# För att köra skriptet, kör kommandot: sudo bash setup_openSUSE_kiosk.sh
# Version 2.4
# Copyright Kasper Sjöström www.kswebb.se
# GNU Affero General Public License (AGPL)
# ==============================================================================

set -e

# Kontrollera att skriptet körs med sudo / root-rättigheter
if [ "$EUID" -ne 0 ]; then
  echo "❌ Error: Detta skript måste köras som root/sudo."
  echo "Kör: sudo bash $0"
  exit 1
fi

echo "=========================================================="
echo "   openSUSE Kiosk Setup Script (Allround)"
echo ""
echo "   Version 2.4 (2026-10-12)"
echo "   Copyright Kasper Sjöström, www.kswebb.se"
echo "   GNU Affero General Public License (AGPL)"
echo "=========================================================="
echo ""

# Fråga efter användarnamn med 'scout' som standard om man enbart trycker Enter
read -rp "Ange användarnamn att konfigurera [standard: scout]: " INPUT_USER
SCOUT_USER="${INPUT_USER:-scout}"
SCOUT_HOME="/home/$SCOUT_USER"

echo "--> Konfigurerar kiosk-miljö för användaren: '$SCOUT_USER' ($SCOUT_HOME)"
echo ""

# Kontrollera att den angivna användaren finns
if ! id "$SCOUT_USER" &>/dev/null; then
    echo "❌ Användaren '$SCOUT_USER' finns inte på systemet."
    echo "Skapa användaren först och logga in en gång så att hemkatalogen initieras."
    exit 1
fi

# Hjälpfunktion för Ja/Nej-frågor
confirm() {
    local prompt="$1"
    local default="$2" # "Y" eller "N"
    local response

    if [ "$default" = "Y" ]; then
        prompt="$prompt [J/n]: "
    else
        prompt="$prompt [j/N]: "
    fi

    while true; do
        read -rp "$prompt" response
        case "$response" in
            [jJ][aA]|[jJ]) return 0 ;;
            [nN][eE][jJ]|[nN]) return 1 ;;
            "")
                if [ "$default" = "Y" ]; then return 0; fi
                if [ "$default" = "N" ]; then return 1; fi
                ;;
            *) echo "Vänligen svara 'j' (ja) eller 'n' (nej)." ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 0. Ändra datornamn (Hostname)
# ------------------------------------------------------------------------------
CURRENT_HOSTNAME=$(hostname)
if confirm "0. Vill du ändra datornamn (nuvarande: '$CURRENT_HOSTNAME')?" "N"; then
    while true; do
        read -rp "    Ange nytt datornamn: " NEW_HOSTNAME
        NEW_HOSTNAME=$(echo "$NEW_HOSTNAME" | tr -d ' ')
        if [ -n "$NEW_HOSTNAME" ]; then
            break
        else
            echo "    ⚠️ Datornamnet kan inte vara tomt."
        fi
    done

    echo "--> Sätter nytt datornamn till '$NEW_HOSTNAME'..."
    hostnamectl set-hostname "$NEW_HOSTNAME"

    # Uppdatera /etc/hosts
    if grep -q "$CURRENT_HOSTNAME" /etc/hosts; then
        sed -i "s/\b$CURRENT_HOSTNAME\b/$NEW_HOSTNAME/g" /etc/hosts
        echo "    ✔ /etc/hosts uppdaterad (ersatte '$CURRENT_HOSTNAME' med '$NEW_HOSTNAME')."
    else
        echo "127.0.0.1   $NEW_HOSTNAME" >> /etc/hosts
        echo "    ✔ Lägg till '$NEW_HOSTNAME' i /etc/hosts."
    fi
fi

# ------------------------------------------------------------------------------
# 1. Installera och autostarta Konversation
# ------------------------------------------------------------------------------
if confirm "1. Vill du installera Konversation och konfigurera autostart?" "Y"; then
    echo "--> Installerar Konversation via zypper..."
    zypper --non-interactive install konversation || true

    AUTOSTART_DIR="$SCOUT_HOME/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"

    DESKTOP_SRC="/usr/share/applications/org.kde.konversation.desktop"
    DESKTOP_DST="$AUTOSTART_DIR/org.kde.konversation.desktop"

    if [ -f "$DESKTOP_SRC" ]; then
        if [ -f "$DESKTOP_DST" ]; then
            if confirm "    Autostartfilen ($DESKTOP_DST) finns redan. Skriva över?" "N"; then
                cp "$DESKTOP_SRC" "$DESKTOP_DST"
                chown "$SCOUT_USER:$SCOUT_USER" "$DESKTOP_DST"
                echo "    ✔ Autostart för Konversation uppdaterad."
            else
                echo "    Hoppar över kopiering av Konversation autostart."
            fi
        else
            cp "$DESKTOP_SRC" "$DESKTOP_DST"
            chown "$SCOUT_USER:$SCOUT_USER" "$DESKTOP_DST"
            echo "    ✔ Autostart för Konversation konfigurerad."
        fi
    else
        echo "    ⚠️ Hittade inte $DESKTOP_SRC."
    fi
fi

# ------------------------------------------------------------------------------
# 2. Skapa autostart för Firefox (reset-kiosk.desktop)
# ------------------------------------------------------------------------------
if confirm "2. Vill du skapa/uppdatera autostart för Firefox (scoutlink.net, scouterna.se och jotajoti.info)?" "Y"; then
    RESET_DESKTOP="$SCOUT_HOME/.config/autostart/reset-${SCOUT_USER}.desktop"
    mkdir -p "$SCOUT_HOME/.config/autostart"

    create_reset_desktop=true
    if [ -f "$RESET_DESKTOP" ]; then
        if ! confirm "    Filen $RESET_DESKTOP finns redan. Skriva över?" "N"; then
            create_reset_desktop=false
            echo "    Hoppar över skapa $RESET_DESKTOP."
        fi
    fi

    if [ "$create_reset_desktop" = true ]; then
        cat << 'EOF' > "$RESET_DESKTOP"
[Desktop Entry]
Type=Application
Name=AutoBrowser
Exec=firefox "http://www.scoutlink.net/guides/irc/" "http://www.scouterna.se/scout-ledare-kar/internationellt/lager/jota-joti/" "https://www.jotajoti.info/"
StartupNotify=false
Terminal=false
EOF
        chown "$SCOUT_USER:$SCOUT_USER" "$RESET_DESKTOP"
        chmod 644 "$RESET_DESKTOP"
        echo "    ✔ $RESET_DESKTOP har skapats."
    fi
fi

# ------------------------------------------------------------------------------
# 3. Konfigurera Firefox-profil & userChrome.css
# ------------------------------------------------------------------------------
if confirm "3. Vill du skapa userChrome.css för att dölja Firefox adressfält och menyer?" "Y"; then
    FIREFOX_DIR="$SCOUT_HOME/.mozilla/firefox"
    if [ -d "$FIREFOX_DIR" ]; then
        PROFILES=$(find "$FIREFOX_DIR" -maxdepth 1 -type d -name "*.*")
        if [ -z "$PROFILES" ]; then
            echo "    ⚠️ Ingen Firefox-profil hittades under $FIREFOX_DIR."
            echo "    Starta Firefox en gång som användaren '$SCOUT_USER' och försök igen."
        else
            for PROF in $PROFILES; do
                CHROME_DIR="$PROF/chrome"
                USERCHROME_FILE="$CHROME_DIR/userChrome.css"
                mkdir -p "$CHROME_DIR"

                create_userchrome=true
                if [ -f "$USERCHROME_FILE" ]; then
                    if ! confirm "    $USERCHROME_FILE finns redan i $(basename "$PROF"). Skriva över?" "N"; then
                        create_userchrome=false
                    fi
                fi

                if [ "$create_userchrome" = true ]; then
                    cat << 'EOF' > "$USERCHROME_FILE"
/* Dölj adressfältet säkert utan att krascha uppstarten */
#urlbar-container {
    visibility: hidden !important;
    width: 0px !important;
    min-width: 0px !important;
}

/* Dölj profilsymbolen (Firefox Account / Sync) */
#fxa-toolbar-menu-button,
#avatar-btn {
    display: none !important;
}

/* Dölj Tillägg-ikonen (pusselbiten) */
#unified-extensions-button {
    display: none !important;
}

/* Dölj plustecknet för ny flik */
#tabs-newtab-button,
#new-tab-button {
    display: none !important;
}

/* Dölj hamburgermenyn (menyknappen längst till höger) */
#PanelUI-button { display: none !important; }

/* Dölj högerklicksmenyn för verktygsfältet och flikraden */
#toolbar-context-menu { display: none !important; }

/* Gör inaktiva flikar synliga (ljusar upp bakgrunden lite) */
.tabbrowser-tab:not([selected="true"]) .tab-background {
    background-color: rgba(255, 255, 255, 0.15) !important;
}
EOF
                    chown -R "$SCOUT_USER:$SCOUT_USER" "$CHROME_DIR"
                    echo "    ✔ userChrome.css har skapats i $(basename "$PROF")."
                fi

                # Aktivera userCustomizations direkt i user.js
                USER_JS="$PROF/user.js"
                echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >> "$USER_JS"
                echo 'user_pref("ui.key.menuAccesskey", 0);' >> "$USER_JS"
                echo 'user_pref("identity.fxaccounts.enabled", false);' >> "$USER_JS"
                chown "$SCOUT_USER:$SCOUT_USER" "$USER_JS"
                echo "    ✔ Inställningar aktiverade i user.js för $(basename "$PROF")."
            done
        fi
    else
        echo "    ⚠️ $FIREFOX_DIR hittades inte. Starta Firefox som användaren '$SCOUT_USER' först."
    fi
fi

# ------------------------------------------------------------------------------
# 4. Lås Firefox policies (policies.json)
# ------------------------------------------------------------------------------
if confirm "4. Vill du applicera och låsa Firefox system-policies (/etc/firefox/policies/policies.json)?" "Y"; then
    POLICY_DIR="/etc/firefox/policies"
    POLICY_FILE="$POLICY_DIR/policies.json"
    mkdir -p "$POLICY_DIR"

    create_policy=true
    if [ -f "$POLICY_FILE" ]; then
        if ! confirm "    Policyfilen $POLICY_FILE finns redan. Skriva över?" "N"; then
            create_policy=false
            echo "    Hoppar över $POLICY_FILE."
        fi
    fi

    if [ "$create_policy" = true ]; then
        cat << 'EOF' > "$POLICY_FILE"
{
  "policies": {
    "Homepage": {
      "URL": "http://www.scoutlink.net/guides/irc/",
      "Locked": true,
      "Additional": [
        "http://www.scouterna.se/scout-ledare-kar/internationellt/lager/jota-joti/",
        "http://www.jotajoti.info/"
        ],
      "StartPage": "homepage"
    },
    "DisableFirefoxAccounts": true,
    "DisableSessionRestore": true,
    "BlockAboutConfig": true,
    "BlockAboutAddons": true,
    "BlockAboutProfiles": true,
    "BlockAboutSupport": true,
    "DisableDeveloperTools": true,
    "Preferences": {
      "toolkit.legacyUserProfileCustomizations.stylesheets": {
        "Value": true,
        "Status": "locked"
      }
    }
  }
}
EOF
        chmod 644 "$POLICY_FILE"
        echo "    ✔ Systempolicies för Firefox sparade i $POLICY_FILE."
    fi
fi

# ------------------------------------------------------------------------------
# 5. Lås KDE-skrivbordet & ta bort högerklick (kdeglobals + desktop-appletsrc + lockCorona)
# ------------------------------------------------------------------------------
if confirm "5. Vill du låsa KDE-skrivbordet och blockera högerklick för användaren '$SCOUT_USER'?" "Y"; then
    KDEGLOBALS="$SCOUT_HOME/.config/kdeglobals"
    APPLETSRC="$SCOUT_HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
    mkdir -p "$SCOUT_HOME/.config"

    # Hantera kdeglobals
    if [ -f "$KDEGLOBALS" ]; then
        chmod 644 "$KDEGLOBALS" 2>/dev/null || true
    fi

    cat << 'EOF' > "$KDEGLOBALS"
[KDE Action Restrictions] [$i]
plasma/plasmashell/unlockedDesktop=false
action/options_show=false
run_command=false
shell_access=false
EOF

    chown root:root "$KDEGLOBALS"
    chmod 444 "$KDEGLOBALS"
    echo "    ✔ $KDEGLOBALS uppdaterad och låst (444)."

    # Hantera plasma-org.kde.plasma.desktop-appletsrc för att ta bort högerklicksmeny på skrivbordet
    if [ -f "$APPLETSRC" ]; then
        chmod 644 "$APPLETSRC" 2>/dev/null || true
    fi

    # Om filen inte finns skapar vi grundstrukturen, annars ser vi till att RightButton inte sätter contextmenu
    if [ ! -f "$APPLETSRC" ]; then
        cat << 'EOF' > "$APPLETSRC"
[ActionPlugins][0]
RightButton;NoModifier=
EOF
    else
        # Ta bort befintlig RightButton-koppling om den finns och lägg till tom eller lägg till sektionen
        if grep -q "\[ActionPlugins\]\[0\]" "$APPLETSRC"; then
            sed -i '/\[ActionPlugins\]\[0\]/,/^\[/ s/RightButton;NoModifier=.*/RightButton;NoModifier=/' "$APPLETSRC"
        else
            sed -i '1i [ActionPlugins][0]\nRightButton;NoModifier=' "$APPLETSRC"
        fi
    fi

    chown root:root "$APPLETSRC"
    chmod 444 "$APPLETSRC"
    echo "    ✔ Skrivbordets högerklick har blockerats i $APPLETSRC och filen har låsts (444)."

    # Kör lockCorona via DBus (Plasma 6 / Plasma 5) för den inloggade sessionen om den är igång
    echo "--> Verkställer lockCorona för Plasma..."
    sudo -u "$SCOUT_USER" qdbus6 org.kde.plasmashell /PlasmaShell evaluateScript 'lockCorona(true)' 2>/dev/null \
    || sudo -u "$SCOUT_USER" qdbus org.kde.plasmashell /PlasmaShell evaluateScript 'lockCorona(true)' 2>/dev/null \
    || echo "    ℹ (Observera: lockCorona körs vid nästa inloggning om användarens session inte var aktiv nu)."
fi

# ------------------------------------------------------------------------------
# 6. Inaktivera Alt+F4 (kglobalshortcutsrc)
# ------------------------------------------------------------------------------
if confirm "6. Vill du inaktivera Alt+F4 / fönsterstängning (kglobalshortcutsrc)?" "Y"; then
    KSHORTCUTS="$SCOUT_HOME/.config/kglobalshortcutsrc"
    mkdir -p "$SCOUT_HOME/.config"

    if [ -f "$KSHORTCUTS" ]; then
        chmod 644 "$KSHORTCUTS" 2>/dev/null || true
    fi

    if [ -f "$KSHORTCUTS" ]; then
        if ! grep -q "\[kwin\]" "$KSHORTCUTS"; then
            cat << 'EOF' >> "$KSHORTCUTS"

[kwin] [$i]
Window Close=none, none, Close Window
EOF
            echo "    ✔ Alt+F4-inaktivering tillagd i $KSHORTCUTS."
        else
            if grep -q "Window Close=" "$KSHORTCUTS"; then
                sed -i 's/Window Close=.*/Window Close=none, none, Close Window/' "$KSHORTCUTS"
            else
                sed -i '/\[kwin\]/a Window Close=none, none, Close Window' "$KSHORTCUTS"
            fi
            echo "    ✔ Sektionen [kwin] uppdaterad i $KSHORTCUTS."
        fi
    else
        cat << 'EOF' > "$KSHORTCUTS"
[kwin] [$i]
Window Close=none, none, Close Window
EOF
        echo "    ✔ $KSHORTCUTS skapad med inaktiverat Alt+F4."
    fi

    chown root:root "$KSHORTCUTS"
    chmod 444 "$KSHORTCUTS"
    echo "    ✔ $KSHORTCUTS ägs nu av root och är skrivskyddad (444)."
fi

echo ""
echo "=========================================================="
echo "   🎉 Konfigurationen är klar för '${SCOUT_USER}'!"
echo "=========================================================="
