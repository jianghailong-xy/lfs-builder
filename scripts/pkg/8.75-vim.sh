#!/usr/bin/env bash
set -euo pipefail
PKG=vim-9.2.0078; cd /sources; test ! -d "$PKG"; tar -xf "$PKG.tar.gz"; cd "$PKG"
echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
./configure --prefix=/usr
make
chown -R tester .
sed '/test_plugin_glvs/d' -i src/testdir/Make_all.mak
set +e; su tester -c 'TERM=xterm-256color LANG=en_US.UTF-8 make -j1 test' > vim-test.log 2>&1; rc=$?; set -e
if [ "$rc" -ne 0 ]; then
  # The summary also lists hundreds of skipped Test_* cases (missing GUI,
  # Windows-only features, and so on).  Only "Found errors in" identifies an
  # actual failed test, so validate that set against the two failures allowed
  # by the LFS book.
  grep -Eq 'Found errors in (Test_client_server_stopinsert|Test_popup_setbuf)\(\)' vim-test.log || exit "$rc"
  if grep -E 'Found errors in Test_[A-Za-z0-9_]+\(\)' vim-test.log \
       | grep -Ev 'Found errors in (Test_client_server_stopinsert|Test_popup_setbuf)\(\)'; then
    exit "$rc"
  fi
fi
make install
ln -sv vim /usr/bin/vi
for L in /usr/share/man/{,*/}man1/vim.1; do ln -sfv vim.1 "${L%vim.1}vi.1"; done
ln -sv ../vim/vim92/doc /usr/share/doc/vim-9.2.0078
printf '%s\n' '" Begin /etc/vimrc' '' 'source $VIMRUNTIME/defaults.vim' 'let skip_defaults_vim=1' '' 'set nocompatible' 'set backspace=2' 'set mouse=' 'syntax on' 'if (&term == "xterm") || (&term == "putty")' '  set background=dark' 'endif' '' '" End /etc/vimrc' > /etc/vimrc
cd /sources; rm -rf "$PKG"
