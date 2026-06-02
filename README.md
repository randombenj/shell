# $ Personal Shell Config

My personal shell config using ...

 - [oh-my-zsh](https://github.com/ohmyzsh/ohmyzsh)
 - [oh-my-posh](https://github.com/JanDeDobbeleer/oh-my-posh)
 - [fzf](https://github.com/junegunn/fzf)

The `.zshrc` file is self installing, meaning that as soon as it's sourced
one can run `update-shell` to install everything else.

### Installation

```sh
git clone https://github.com/randombenj/shell.git ~/Work/personal/shell
ln -s ~/Work/personal/shell/.zshrc ~/.zshrc
source ~/.zshrc
update-shell
```
