## Next Step 1

We are in need of a system that allows us to add `"ENABLE_TESTING_SEARCH_PATHS" : "YES"` to the appropriate projects.

Swift Package Manager or the Xcode build system does this automatically by somehow automatically accounting for `import XCTest` and related declarations.

Or this might be something that we need a config file for, like how native tuist would allow you to add configurations by target name.

## Next Step 2

How should we handle packages that don't list a platform? I would assume we just use the minimum for all targets. Perhaps specifying a global minimum is necessary. Again we might need a config file for this, or just a parameter.
