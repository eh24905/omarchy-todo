# Todo

A todo list and scratch pad for the Omarchy shell. One window with two tabs:

- **Tasks**: an "Add a task…" input with focus, then three sections from top to bottom: **Next**, **Backlog** and **Done**.
- **Notes**: a plain-text scratch pad that saves as you type.

Data is plain text, so you can edit it in any editor or sync it:

- `~/.local/share/omarchy-todo/todo.txt` ([todo.txt](https://github.com/todotxt/todo.txt) format: `x <date>` = done, `(A)` = next, no prefix = backlog)
- `~/.local/share/omarchy-todo/notes.md`

## Install (dev)

```sh
./install.sh   # copies into ~/.config/omarchy/plugins/eh24905.todo and enables it
```

## Bar icon

A checklist icon shows the number of tasks in Next. Left-click opens the full window; right-click opens quick add.
`install.sh` places it on the right side of the bar. Move it with, for example:

```sh
omarchy bar move eh24905.todo --section center
```

## Keybindings

Add to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + T", "Quick add todo", [[omarchy-shell shell toggle eh24905.todo '{"mode":"quick"}']])
o.bind("SUPER + SHIFT + ALT + T", "Todo", "omarchy-shell shell toggle eh24905.todo '{}'")
```

Quick add is a single input, like the reminders prompt: type, press Enter, and it closes.

## Keys

| Where | Key | Action |
|---|---|---|
| Input | `Enter` / `Shift+Enter` | Add to Backlog / add to Next (`(A) foo` also goes to Next) |
| Input | `↑` | Move into the list (from the bottom) |
| Input | `Esc` | Cancel edit, then clear text, then close |
| List | `↑↓` or `j k` | Move the cursor |
| List | `Shift`/`Alt` + `↑↓` | Reorder within the section |
| List | `Space` / `x` | Toggle done |
| List | `n` / `b` | Move to Next / Backlog |
| List | `Enter` / `e` | Edit the task |
| List | `Del` / `d`, `Shift+Del` | Delete the task, clear all done tasks |
| List | `Esc` / `i` | Back to the input |
| Anywhere | `Tab` (tasks), `Ctrl+Tab`, `Alt+1`/`Alt+2` | Switch tabs |

Mouse: click the margin beside a task (where `(A)` or `x` shows) to toggle done, double-click to edit, and hover a row to move or delete it.
