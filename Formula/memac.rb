# Homebrew formula for memac — local-first memory for AI coding agents (Apple Silicon only).
#
# PREBUILT BINARY BOTTLE. The `url` is a release-hosted tarball of already-built binaries + the
# vendored runtime assets (bge model, sqlite-vec dylib, the zsh capture hook). There is NO build
# step here: no git clone, no `git lfs pull`, no cargo/npm, no network beyond fetching the tarball
# (which Homebrew does pre-sandbox). This sidesteps Homebrew's build sandbox entirely — the reason
# an asset-heavy, private-LFS project could never `git lfs pull` inside `install`.
#
# Principle V (local-first, no egress): the model/dylib ride INSIDE the tarball, sha256-verified by
# Homebrew on download and again by the daemon at load. Nothing is fetched from a model hub, ever.
#
# INSTALL COMMAND: `brew install sibyllinex/tap/memac`, then the two user-run setup commands that
# `post_install` prints (also in `caveats`): restage the runtime assets into
# `~/Library/Application Support/mem-mac` and wire the Claude Code hook + MCP into
# `~/.claude/settings.json` and the shell-capture block into `~/.zshrc`.
#
# post_install cannot do those home writes itself (tanxarx/memac#55). Homebrew sandboxes it with
# `sandbox-exec`, which denies the real home, and Homebrew 7 also points its HOME at a throwaway
# temp dir. A home write there silently lands in that decoy home, which Homebrew deletes, while
# the log reads as success. `HOMEBREW_NO_SANDBOX` is not an escape hatch: it was removed from
# Homebrew at 2.2.12 and is ignored. So post_install makes no home writes; it only warns.
#
# Naming: the package/command is `memac`; the binaries are still `memmac*` — `bin.install_symlink`
# aliases `memac` -> `memmac`. The Claude Code hook + MCP keys stay `memmac`.
class Memac < Formula
  desc "Local-first memory layer for AI coding agents"
  homepage "https://github.com/sibyllineX/memac"
  url "https://github.com/sibyllineX/memac/releases/download/v0.1.1/memac-0.1.1.arm64.tar.gz"
  sha256 "f0cd50d730a6c4ba8e2c8280f842865828d5c23fe3e7b2b6cdd3ef45cbffa80d"
  version "0.1.1"
  license any_of: ["MIT", "Apache-2.0"]

  depends_on arch: :arm64
  depends_on :macos
  depends_on "node" # the user-run install-hooks step reuses the tested TS installer

  def install
    # Prebuilt binaries — just place them. `memac` is the command; the crates stay `memmac*`.
    bin.install "bin/memmacd", "bin/memmac", "bin/memmac-mcp", "bin/memmac-hook"
    bin.install_symlink "memmac" => "memac"
    # The compiled TS installer + the runtime assets (model, dylib, zsh capture hook), stashed for
    # the user-run setup. `memmac-hook.zsh` MUST ship here: the zshrc block `source`s it by this path.
    libexec.install "dist"
    (libexec/"assets").install "assets/models", "assets/sqlite-vec", "assets/memmac-hook.zsh"
  end

  # The two user-run steps that wire this keg into the real home: restage the runtime assets
  # (sha256 is re-verified at load) and wire the hooks + MCP against the stable opt_bin. Both are
  # idempotent and preserve the user's other hooks/servers (the tested TS merge).
  def manual_setup_commands
    <<~EOS.chomp
      cp -R #{opt_libexec}/assets/models #{opt_libexec}/assets/sqlite-vec "$HOME/Library/Application Support/mem-mac/assets/"
      node #{opt_libexec}/dist/cli.js install-hooks --bin-dir #{opt_bin}
    EOS
  end

  # No home writes here (tanxarx/memac#55): see the header. Say plainly that the user must run them.
  def post_install
    opoo <<~EOS
      memac hooks were NOT wired and runtime assets were NOT staged.
      Homebrew runs post_install in a sandbox with a temporary HOME, so it cannot reach yours.
      Run these yourself (idempotent; re-run after every upgrade):
      #{manual_setup_commands}
    EOS
  end

  service do
    run [opt_bin/"memmacd", "--data-dir", "#{Dir.home}/Library/Application Support/mem-mac/data"]
    keep_alive true
    run_at_load true
    working_dir Dir.home
    log_path "#{Dir.home}/Library/Application Support/mem-mac/logs/memmacd.out.log"
    error_log_path "#{Dir.home}/Library/Application Support/mem-mac/logs/memmacd.err.log"
  end

  def caveats
    <<~EOS
      memac (Apple Silicon, prebuilt bottle) is installed.

      REQUIRED — stage the assets and wire the hooks into your home directory:
      #{manual_setup_commands.gsub(/^/, "  ")}

      Homebrew runs post_install inside a sandbox with a temporary HOME, so these steps cannot
      be automated. They are idempotent — re-run them after every upgrade.

      KNOWN LIMITATION — the commands above refresh an existing
      ~/Library/Application Support/mem-mac/; they do not create the data layout a
      never-installed machine needs. On a fresh machine, use memac's npm installer.

      Start the memory daemon (a per-user LaunchAgent):
        brew services start memac

      Then open a NEW Claude Code session in your repo. Verify any time with:
        memac doctor

      Homebrew cannot run scripts on `brew uninstall`, so remove the Claude Code hook + MCP entry
      first (and stop the daemon with `brew services stop memac`):
        node #{opt_libexec}/dist/cli.js uninstall-hooks
    EOS
  end

  test do
    assert_path_exists bin/"memmacd"
    assert_match "ladder", shell_output("#{bin}/memac doctor 2>&1 || true")
  end
end
