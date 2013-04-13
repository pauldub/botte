.PHONY: run

all: run

run: 
	dart --checked botte.dart

deps:
	pub install
