# Specmatic Loop Test

All of Specmatic is the System Under Test and is treated as a black box. System is run in Docker Compose and HTTP
request/response pairs are captured by `mitmproxy.`

## Problem Statment

Given a simple openapi 3.0 spec file, start a stub server and then using the same spec file run tests against that stub server to check
1. Does the tests pass.
2. Did the test send the right request (payload + headers)
3. Did the stub respond back with the right response (payload + headers)

## Requirements

1. Docker Compose
2. Ruby 4.0.1

## Running

1. `bundle install`
2. `bundle exec rspec`
