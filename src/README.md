# Git submodule
  * Add a submodule
   ```
   git submodule init
   git submodule add https://github.com/xxxx.git
   git add .gitmodules
   git add path/to/submodule
   ```
  * Remove a submodule 
   ```
   git submodule deinit -f path/to/submodule
   rm -rf .git/modules/path/to/submodule
   git rm -f path/to/submodule
   ```

  * clone all submodules
  ```
  git clone --recurse-submodules git@github.com:avinzhang/confluent.git
  ```
  or
  ```
  git submodule update --init
  ```
