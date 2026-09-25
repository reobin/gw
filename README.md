# gw

Paste a GitHub PR URL, land in a worktree for its branch.

```sh
gw https://github.com/<owner>/<repo>/pull/<id>
```

`gw` resolves the PR's head branch, finds your local checkout of the repo by
remote URL, and asks [`git-wt`](https://github.com/k1LoW/git-wt) to create
the worktree when needed; gw then cds into it. Existing branches are updated
to the PR's latest head, including after a force-push, unless they hold
commits of your own. Merged or closed PRs print a notice and continue.

Fork PRs are checked out read-only as a local `pr-<id>` branch; gw does not
add fork remotes, so you cannot push back to them from that branch.

## Install

Requires zsh. [`zoxide`](https://github.com/ajeetdsouza/zoxide) is optional
and speeds up checkout discovery.

**Oh My Zsh / antigen / zplug:** these load `gw.plugin.zsh` automatically.

```sh
git clone https://github.com/reobin/gw.git ~/.local/share/gw
# oh-my-zsh custom plugin, then add gw to plugins=(...):
ln -s ~/.local/share/gw ~/.oh-my-zsh/custom/plugins/gw
```

**Manual:** source it from your `.zshrc`.

```sh
source ~/.local/share/gw/gw.plugin.zsh
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
