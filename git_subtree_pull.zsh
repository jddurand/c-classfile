#!zsh -x

git fetch origin
foreach this (cmake-utils genericLogger genericStack genericHash) {
  git fetch $this master
}

git clean -ffdx
foreach this (cmake-utils genericLogger genericStack genericHash) {
  git subtree pull --prefix 3rdparty/github/$this $this master --squash
}

exit 0
