# Repository tools

- `plasma-capture.sh PLASMOID_DIR OUTPUT.png [full|horizontal|vertical] [seconds]` installs a uniquely named temporary copy of any applet in this repo, captures its popup (`full`, via `plasmawindowed`) or its panel representation (a throwaway top or left panel), and removes both on exit. It grabs only the applet's own pixels.
- Widget-specific tools live in each widget's `.agents/tools/`.
