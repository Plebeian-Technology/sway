---
lat:
  mode: explanation
---

# Why system specs give each parallel worker its own chromedriver port block

`spec/support/system_driver.rb` picks each `parallel_tests` worker's chromedriver port from `9515 + (ENV["TEST_ENV_NUMBER"].to_i * 10)` instead of letting Selenium pick.

Every worker would otherwise start chromedriver on the same port. Selenium defaults to a flat 9515 (`Service#initialize` does `port ||= DEFAULT_PORT`) and then walks upward with `PortProber`, which binds a probe socket and closes it again — so two workers starting at once can both read the same port as free. The loser cannot bind, but Selenium's `connect_until_stable` finds the WINNER's chromedriver already answering there and calls the service up, leaving two workers driving one process. When the owner exits, every request from the other worker dies `ECONNREFUSED` for the rest of its run: every failure contiguous to the end of one shard.

## Why the block is 10 wide, not 1

`PortProber` still walks upward from whatever base it is given, so adjacent single-port bases could meet in the middle. A block of 10 per worker gives each one room to walk without colliding with its neighbor.

This is passed on the Selenium Manager path too — there is no packaged chromedriver on a macOS host, and the race is the same there.
