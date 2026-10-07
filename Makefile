SHELL := /bin/bash

init:
	python3 ./createEnv.py
	source ./.venv/bin/activate && \
	pip install --upgrade pip && \
	pip install .
update:
	source ./.venv/bin/activate && \
	pip install .
clean:
	rm -R -f ./.venv
	rm -R -f __pycache__
	rm -R -f *.egg-info
devel: init
	source ./.venv/bin/activate
	pip install --no-deps -e ./

develupdate: update
	source ./.venv/bin/activate
	pip install --no-deps -e ./
