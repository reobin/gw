# gw

paste a GitHub PR URL, land in a worktree for its branch.

```sh
gw https://github.com/<owner>/<repo>/pull/<id>
```

finds your local checkout, creates the worktree if needed, cds into it.

## install

needs git, gh. optional: git-wt, zoxide.

clone it anywhere:

```sh
git clone https://github.com/reobin/gw.git ~/.local/share/gw
```

then source it from `~/.bashrc` or `~/.zshrc`:

```
. ~/.local/share/gw/gw.sh
```

## configure

export these from the same rc file (`~/.bashrc` or `~/.zshrc`):

```sh
export GW_ROOTS="$HOME/dev $HOME/GitHub $HOME/code"   # where to look
export GW_CLONE_ROOT=$HOME/dev                        # where to clone
```

defaults to the above. order: current checkout, zoxide, GW_ROOTS scan, clone.

fork PRs checkout read-only as `pr-<id>`. branches with your own commits are left alone.

## license

mit.
