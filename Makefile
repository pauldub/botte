.PHONY: run deps

all: run

run: 
	dart --checked botte.dart

deps:
	pub install
