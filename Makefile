.PHONY: lint test run

lint:
		luacheck lua/llm-sidekick plugin/

test:
		nvim --headless --noplugin -u scripts/minimal_init.vim -c "PlenaryBustedDirectory lua/llm-sidekick/spec/ { minimal_init = './scripts/minimal_init.vim' }"
