if [[ -f "$FARADAI_USER_ZDOTDIR/.zshrc" ]]; then
  source "$FARADAI_USER_ZDOTDIR/.zshrc"
fi

if [[ -n ${FARADAI_DEV_PATH-} ]]; then
  # User startup files may reorder PATH; restore the dev shell first.
  typeset +U path 2>/dev/null
  export PATH="${FARADAI_DEV_PATH}:${PATH}"
fi
