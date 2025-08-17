# Setup guide

Here's what you'll need:
- A C/C++ build environment. This means `gcc`, `g++`, `make`, etc.
- The Bluespec compiler (`bsc`). See <https://github.com/B-Lang-org/bsc>.
  - You'll definitely need this to be productive. At least you want to be able to run unit tests (testbenches).
- The libraries in `bsc-contrib`. See <https://github.com/B-Lang-org/bsc-contrib>.
  - Be careful about how you install these. They should probably end up going into the same root as `bsc`.
- Connectal. This actually requires a few other things that are not very well-documented.
  - `fpgamake` in <https://github.com/cambridgehackers/fpgamake>. (Implicitly required by Connectal.)
  - `buildcache` in <https://github.com/cambridgehackers/buildcache>. (Not really used anymore, but Connectal sometimes looks for it.)
  - `connectal` itself. The official repository exists at <https://github.com/cambridgehackers/connectal>, but sometimes you'll run into issues. Someone in your research lab probably has a fork that works. For example, I have one with a PR I never successfully merged: <https://github.com/cambridgehackers/connectal/pull/198>.
  - `fpgajtag` in <https://github.com/cambridgehackers/fpgajtag>. (Needed only if you're actually connecting to an FPGA.)
  - These should probably all be installed at the same root due to some assumptions made by Connectal.

If you're using one of the shared machines in the lab, these things are likely already set up for you.
You just need to know where they are stored. (Ask someone.)
Alternatively, you might be using a cloud image that already has these things set up for you.
Either way, you'll probably need to develop the skills to troubleshoot issues as they come up.

You'll likely need to set the following variables in your `.bashrc` or `.bash_profile` or `.zshrc` to point to your installed tools.
```sh
# Point to the root of your Bluespec installation. (The one that contains `bin/`, `doc/`, `lib/`.)
# On audacity machine, `/opt/Bluespec/Bluespec-2023.07/` has a fairly complete installation (including `bsc-contrib` libraries).
export BSPATH="$HOME/.local/share/bsc/latest"

# Point to where Bluespec libraries are installed. Usually it's the root folder followed by `lib`.
export BLUESPECDIR="$BSPATH/lib"

# Point to wherever you cloned these things. Connectal expects these variables.
# I recommend just cloning these yourselves. I personally put all of them in `$HOME/.local/share/` but you do you.
export CONNECTALDIR="$HOME/.local/share/connectal"
export FPGAMAKE="$HOME/.local/share/fpgamake"
export FPGAJTAG="$HOME/.local/share/fpgajtag"
export BUILDCACHE="$HOME/.local/share/buildcache"

# Add `bsc` to PATH so you can actually run it.
export PATH="$BSPATH/bin:$PATH"

# You'll probably want to add the paths containing `fpgamake`, `fpgajtag`, and `buildcache` binaries/scripts as well.
# So, instead, I created symlinks in my `$HOME/.local/bin/`:
export PATH="$HOME/.local/bin:$PATH"

# Actually, I really like installilng things in `$HOME/.local/`, so I set up many things... like these:
export CPATH="$HOME/.local/include:$CPATH"
export LIBRARY_PATH="$HOME/.local/lib:$LIBRARY_PATH"
export LIBRARY_PATH="$HOME/.local/lib64:$LIBRARY_PATH"
export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="$HOME/.local/lib64:$LD_LIBRARY_PATH"

# If you're running on real FPGAs on CSAIL-provided machines like `audacity`, you'll probably have to set these.
# `audacity` uses account `1709`. I don't know about other machines.
export LM_LICENSE_FILE=1709@multiplicity.csail.mit.edu:$LM_LICENSE_FILE
export XILINX_HOME=/opt/Xilinx/

# Some more useful things you'll want to have
export EDITOR=vim
export VISUAL=vim
alias ls='ls --color=auto'
alias ll='ls -alF'
alias grep='grep --color=auto'
```

If you end up setting things up on Amazon, see `AWS.md` for additional guide.
