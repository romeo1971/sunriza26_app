.PHONY: check-stack install-git-hooks

check-stack:
	@bash scripts/check_stack_versions.sh

install-git-hooks:
	@bash scripts/install_git_hooks.sh


