# bash_progress_bar

> Note: There is now also this [python implementation](https://github.com/pollev/python_progress_bar)

This script is intended to be sourced by other bash scripts. It will allow those scripts to create a progress bar which does not interfere with the scrolling output of the script. The look and feel for this progress bar is based on the progress bar used by APT.

What makes this progress bar different from the basic terminal progress bars which use carriage return (`\r`) to overwrite their own line, is that this progress bar does not interfere with the normal output of your script. This makes it very easy to update existing scripts to use this bar without having to worry about the scrolling of your output.

## Usage

Source this script, then use the provide commands as follows.

1. create progress bar with:

   ```shell
   create_progress_bar --eta --trap --precision 2 -N 100 MyTask
   ```

1. update progress bar with:

   ```shell
   draw_progress_bar 15
   ```

   or you may want to provide a message for each progress update.

   ```shell
   draw_progress_bar 20 'current task 20'
   ```

1. when finish all the tasks, please clear the progress bar:

   ```shell
   destroy_scroll_area
   ```

If your program is interactive, and may accept user's input during the
progress, you can pause the progress bar, and get user's input, and then
continue to update it.

```shell
block_progress_bar 45
```

which will turns the progress bar yellow to indicate some action is requested
from the user. After that, continue your tasks keeping progress bar updated.

```shell
draw_progress_bar 90
```

An example can be viewed in `test_bar.sh`. The actual implementation can be found in `progress_bar.sh`

Example output:

![demo](example.gif)
