#!/usr/bin/env ruby
# frozen_string_literal: true

# Fixture for boot_spec: a minimal entry point. Launched with system Ruby it
# should come back running a current one, with its arguments intact. Kept
# 2.6-parseable for the same reason the real entry points are.

require_relative '../../lib/buttercut/boot'

print RUBY_VERSION, ' ', ARGV.join(' ')
