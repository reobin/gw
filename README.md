# gw

Paste a GitHub PR URL, land in a worktree for its branch.

```sh
gw https://github.com/<owner>/<repo>/pull/<id>
```

`gw` resolves the PR's head branch, finds your local checkout of the repo by
remote URL, and asks [`git-wt`](https://github.com/k1LoW/git-wt) to create
the worktree when needed; gw then cds into it. When git-wt is not installed,
gw falls back to plain `git worktree add` under `.wt`. Existing branches are updated
to the PR's latest head, including after a force-push, unless they hold
commits of your own. Merged or closed PRs print a notice and continue.

Fork PRs are checked out read-only as a local `pr-<id>` branch; gw does not
add fork remotes, so you cannot push back to them from that branch.

## Install

Requires sh, git. gh is optional (full fidelity with it; without it gw
runs in limited mode: `pr-<id>` branch for all PRs, no closed/merged
status, no rename-following, private-repo clone via git credential helper
only). [`zoxide`](https://github.com/ajeetdsouza/zoxide) is optional
and speeds up checkout discovery.

**Oh My Zsh / antigen / zplug:** these load `gw.plugin.zsh` automatically.

```sh
git clone https://github.com/reobin/gw.git ~/.local/share/gw
# oh-my-zsh custom plugin, then add gw to plugins=(...):
ln -s ~/.local/share/gw ~/.oh-my-zsh/custom/plugins/gw
```

**Manual:** source `gw.sh` from your shell rc.

```sh
. ~/.local/share/gw/gw.sh                  # sh, bash, dash
emulate sh -c '. ~/.local/share/gw/gw.sh'  # zsh
```

## Configure

```sh
GW_ROOTS="~/GitHub ~/code ~/src"  # dirs scanned for checkouts
GW_CLONE_ROOT=~/GitHub            # where to clone when no checkout exists
```

Lookup order: current checkout, `zoxide` history, `GW_ROOTS` scan, then clone
into `GW_CLONE_ROOT`. If several checkouts match, the first hit in that
order wins.

## License

MIT.
