#!/bin/bash

set -e

script_path="$(readlink -f "${BASH_SOURCE[0]}")"
dotfiles_dir="$(dirname "$script_path")"

link_mode="safe"
check_repo=false
link_conflicts=0

while (( $# > 0 )); do
	case "$1" in
		--adopt-local)
			if [[ "$link_mode" == "force" ]]; then
				echo "--adopt-local and --force-repo cannot be used together." >&2
				exit 2
			fi
			link_mode="adopt"
			;;
		--force-repo)
			if [[ "$link_mode" == "adopt" ]]; then
				echo "--adopt-local and --force-repo cannot be used together." >&2
				exit 2
			fi
			link_mode="force"
			;;
		--check-repo)
			check_repo=true
			;;
		--help)
			cat <<EOF
Usage: $0 [--adopt-local | --force-repo] [--check-repo]

  --adopt-local  Copy conflicting local files into the dotfiles repository.
  --force-repo   Replace conflicting local files with repository symlinks.
  --check-repo   Fetch and report repository sync status.
EOF
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			exit 2
			;;
	esac
	shift
done

# check for curl and zsh, if either is missing, install them
if ! command -v curl >/dev/null 2>&1; then
	sudo apt-get update && sudo apt-get install -y curl
fi
if ! command -v zsh >/dev/null 2>&1; then
	sudo apt-get update && sudo apt-get install -y zsh
fi


download() {
    curl -fsSL "$1"
}


link_file() {
	local source="$1"
	local destination="$2"

	mkdir -p "$(dirname "$destination")"

	if [[ ! -e "$source" ]]; then
		echo "Repository file does not exist: $source" >&2
		return
	fi

	if [[ -L "$destination" && "$(readlink "$destination")" == "$source" ]]; then
		return
	fi

	if [[ ! -e "$destination" && ! -L "$destination" ]]; then
		ln -s "$source" "$destination"
		return
	fi

	if diff -qr "$destination" "$source" >/dev/null 2>&1; then
		rm -rf "$destination"
		ln -s "$source" "$destination"
		return
	fi

	case "$link_mode" in
		adopt)
			rm -rf "$source"
			cp -aL "$destination" "$source"
			rm -rf "$destination"
			ln -s "$source" "$destination"
			echo "Adopted local changes: $source"
			;;
		force)
			rm -rf "$destination"
			ln -s "$source" "$destination"
			echo "Replaced local file with repository link: $destination"
			;;
		safe)
			echo "Local file differs from the repository copy: $destination" >&2
			echo "Review it, then run $0 --adopt-local or $0 --force-repo." >&2
			((link_conflicts += 1))
			;;
	esac
	return 0
}

check_repository() {
	local repository="$dotfiles_dir"
	local upstream
	local behind
	local ahead
	local changes

	if ! upstream="$(git -C "$repository" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"; then
		echo "Dotfiles repository has no upstream branch configured." >&2
		return
	fi

	git -C "$repository" fetch --quiet
	behind="$(git -C "$repository" rev-list --count "HEAD..$upstream")"
	ahead="$(git -C "$repository" rev-list --count "$upstream..HEAD")"
	changes="$(git -C "$repository" status --short)"

	if [[ -n "$changes" ]]; then
		echo "Dotfiles repository has uncommitted changes:"
		printf '%s\n' "$changes"
	fi
	if (( behind > 0 )); then
		echo "Dotfiles repository is $behind commit(s) behind $upstream; review and pull."
	fi
	if (( ahead > 0 )); then
		echo "Dotfiles repository is $ahead commit(s) ahead of $upstream; review and push."
	fi
	if [[ -z "$changes" ]] && (( behind == 0 && ahead == 0 )); then
		echo "Dotfiles repository is clean and up to date."
	fi
}

mkdir -p "$HOME/.config"

#####
# git
#####

link_file "$dotfiles_dir/.config/git/config" "$HOME/.config/git/config"

if [[ ! -f "$HOME/.config/git/config-personal" ]]; then
    echo "Creating personal git config at $HOME/.config/git/config-personal"
	touch "$HOME/.config/git/config-personal"
    # and prompt the user for their name and email
    read -rp "Enter your name for .gitconfig-personal: " git_name
    read -rp "Enter your email for .gitconfig-personal: " git_email
    cat <<EOF > "$HOME/.config/git/config-personal"
[user]
	name = $git_name
	email = $git_email
EOF
fi


########
# zellij
########
if ! command -v zellij >/dev/null 2>&1 || [[ "$software_version_check_due" == true ]]; then
	zellij_archive="zellij-x86_64-unknown-linux-musl.tar.gz"
	zellij_checksum="zellij-x86_64-unknown-linux-musl.sha256sum"
	zellij_tmp="$(mktemp -d)"
	zellij_binary_dir="$zellij_tmp/target/x86_64-unknown-linux-musl/release"
	zellij_release_url="https://github.com/zellij-org/zellij/releases/latest/download"
	trap 'rm -rf "$zellij_tmp"' EXIT

	download "$zellij_release_url/$zellij_archive" > "$zellij_tmp/$zellij_archive"
	download "$zellij_release_url/$zellij_checksum" > "$zellij_tmp/$zellij_checksum"
	mkdir -p "$zellij_binary_dir"
	tar -xzf "$zellij_tmp/$zellij_archive" -C "$zellij_binary_dir" zellij
	(cd "$zellij_tmp" && sha256sum --quiet -c "$zellij_checksum")

	if ! command -v zellij >/dev/null 2>&1 ||
		[[ "$(zellij --version)" != "$("$zellij_binary_dir/zellij" --version)" ]]; then
		mkdir -p "$HOME/.local/bin"
		install -m 755 "$zellij_binary_dir/zellij" "$HOME/.local/bin/zellij"
	fi

	rm -rf "$zellij_tmp"
	trap - EXIT
fi

mkdir -p "$HOME/.config/zellij"
link_file "$dotfiles_dir/.config/zellij/config.kdl" "$HOME/.config/zellij/config.kdl"

#####
# zsh
#####
# install zsh if necessary 
if ! command -v zsh >/dev/null 2>&1; then
	sudo apt-get update && sudo apt-get install -y zsh
fi

# set current user's shell to zsh if necessary
if [[ "$SHELL" != "$(command -v zsh)" ]]; then
    chsh -s "$(command -v zsh)"
fi

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
	sh -c "$(download https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

link_file "$dotfiles_dir/.zshrc" "$HOME/.zshrc"
link_file "$dotfiles_dir/.oh-my-zsh/themes/" "$HOME/.oh-my-zsh/themes/ebnx.zsh-theme"

if [[ "$check_repo" == true ]]; then
	check_repository
fi
