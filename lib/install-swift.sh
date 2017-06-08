#!/bin/bash

function installSwift {
  # Make sure correct Swift version is installed
  # -s flag (skip-existing) prevents failure when build already installed
  local version=`cat .swift-version`
  case `uname` in
  Linux)
    swiftenv install $version -s
    ;;
  Darwin)
    # Must be run with sudo on Mac, as builds are installed globally
    sudo swiftenv install $version -s
    ;;
  esac
}
