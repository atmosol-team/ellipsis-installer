#!/usr/bin/env bash

# Defaults
PACKAGES='git@bitbucket.org:atmosol/dot-desktop.git'
SSH_KEY=$HOME/.ssh/id_rsa
SSH_COMMENT="$(whoami)@$(hostname)"

if [ -z "$ELLIPSIS_USER" ]; then
    ELLIPSIS_USER='thomshouse-ellipsis'
fi

# Check for ellipsis.sh
if [ -x "$HOME/.ellipsis/bin/ellipsis" ]; then
    echo -e "\nExisting ellipsis install found. Not installing.\n"
    echo -e "If you wish to install these packages, you may do so by running:\n"
    if [ "$(command -v ellipsis)" ]; then
        echo -e "  ellipsis install $PACKAGES\n"
    else
        echo -e "  $HOME/.ellipsis/bin/ellipsis install $PACKAGES\n"
    fi
    exit 0
fi

# Check SSH key pair
if [ ! -f $SSH_KEY ] || [ ! -f $SSH_KEY.pub ]; then
    echo ""
    # If default pair not found, prompt for location
    read -e -p "SSH key location: [~/.ssh/id_rsa] " SSH_KEY
    if [ -z "$SSH_KEY" ]; then
        # If unspecified, fallback to default location
        SSH_KEY=$HOME/.ssh/id_rsa
    fi

    # If neither key is found, generate a new key
    if [ ! -f $SSH_KEY ] && [ ! -f $SSH_KEY.pub ]; then
        # Get a comment for the new key
        read -e -p "Comment to identify new SSH key: [$(whoami)@$(hostname)] " SSH_COMMENT
        if [ -z "$SSH_COMMENT" ]; then
            # Default to username@hostname
            SSH_COMMENT="$(whoami)@$(hostname)"
        fi
        SSH_DEFAULT_COMMENT="$SSH_COMMENT"
        # Generate the key
        ssh-keygen -f "$SSH_KEY" -t rsa -C "$SSH_COMMENT"
    elif [ ! -f $SSH_KEY ] || [ ! -f $SSH_KEY.pub ]; then
        # If one key is found but not the other, abort...  Something strange is going on.
        echo -e "\nERROR: Public and private key mismatch. Please check your SSH keys.\n"
        exit 1
    fi
fi

# Start SSH agent and add key -- or else this could get frustrating
echo -e "\nStarting temporary SSH agent...\n"
eval `ssh-agent` &>/dev/null
ssh-add "$SSH_KEY"

# Test to see if SSH key needs to be added to Bitbucket
ssh -i "$SSH_KEY" -T git@bitbucket.org 2>/dev/null
if [ $? -eq 255 ]; then
    # SSH key doesn't connect to Bitbucket -- Prompt to upload
    echo -e "\nYour SSH public key ($SSH_KEY.pub) does not appear to be associated with a Bitbucket account."
    echo -e "You will need to add your public key to your Bitbucket account.\n"
    
    # Try to be helpful and copy the public key to clipboard per OS
    if [ "$(command -v clip.exe)" ]; then
        # WSL
        cat "$SSH_KEY.pub" | tr -d "\n" | clip.exe
        echo -e "For your convenience, your public key has been copied to your clipboard.\n"
    elif [ "$(command -v pbcopy)" ]; then
        # MacOS
        cat "$SSH_KEY.pub" | tr -d "\n" | pbcopy
        echo -e "For your convenience, your public key has been copied to your clipboard.\n"
    elif [ "$(command -v xclip)" ]; then
        # Linux
        cat "$SSH_KEY.pub" | tr -d "\n" | xclip -selection c
        echo -e "For your convenience, your public key has been copied to your clipboard.\n"
    elif [ "$(command -v edit)" ]; then
        # If clipboard isn't available, offer to open in the default editor
        read -e -p "Open public key in editor for copying? [Y/n] " OPEN_KEY_IN_EDITOR
        if [[ ! $OPEN_KEY_IN_EDITOR =~ ^[Nn][Oo]?$ ]]; then
            edit "$SSH_KEY.pub"
        fi
        echo ""
    fi

    # Optionally open up Bitbucket URLs if supported
    if [ -z "$BROWSER" ]; then
        # Look for common browsers/OS support if not set in environment
        browsers=( "explorer.exe" "open" "xdg-open" "gnome-open" "browsh" "w3m" "links2" "links" "lynx" )
        for b in "${browsers[@]}"; do
            if [ "$(command -v $b)" ]; then
                BROWSER="$b"
                break
            fi
        done
    fi
    if [ -n "$BROWSER" ]; then
        # Browser found -- Ask to open the Bitbucket URL
        prompt_bitbucket=1
        while [ $prompt_bitbucket -eq 1 ]; do
            read -e -p "Open Bitbucket URL for adding SSH key? [Y/n/?] " open_bitbucket_url
            case $open_bitbucket_url in
                [Nn]|[Nn][Oo])
                    echo ""
                    prompt_bitbucket=0
                    ;;
                [?]|[Hh]|[Hh][Ee][Ll][Pp])
                    echo -e "\nOpening Bitbucket Help page...\n"
                    $BROWSER "https://support.atlassian.com/bitbucket-cloud/docs/set-up-an-ssh-key/"
                    ;;
                *)
                    echo -e "\nOpening Bitbucket SSH Keys page...\n"
                    $BROWSER "https://bitbucket.org/account/settings/ssh-keys/"
                    prompt_bitbucket=0
                    ;;
            esac
        done
    fi

    # Pause to give time to upload the key
    read -n 1 -s -r -p "Please add your public key to your Bitbucket account, then press any key to continue..."
    read -s -t 0 # Clear any extra keycodes (e.g. arrows)
    echo ""
    # Retest key and loop until we have success
    ssh -i "$SSH_KEY" -T git@bitbucket.org 2>/dev/null
    while [ $? -eq 255 ]; do
        read -n 1 -s -r -p "Please add your public key to your Bitbucket account, then press any key to continue..."
        read -s -t 0 # Clear any extra keycodes (e.g. arrows)
        echo ""
        ssh -i "$SSH_KEY" -T git@bitbucket.org 2>/dev/null
    done
fi
# End BitBucket

echo -e "\nInstalling ellipsis with the following packages: $PACKAGES...\n"

curl -sL ellipsis.sh | ELLIPSIS_USER="$ELLIPSIS_USER" PACKAGES="$PACKAGES" sh

# Stop the SSH agent
ssh-agent -k &>/dev/null
echo -e "\nTemporary SSH agent stopped.\n"
