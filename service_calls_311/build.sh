#!/usr/bin/env bash
# coding: utf-8

docker build \
    -t vykuang/service-calls:base \
    -f dockerfile \
    .
