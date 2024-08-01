#!/usr/bin/env python3

import subprocess
import sys


def get_focused_monitor(monitor_info):
  """
  This function parses the provided text and returns the ID of the focused monitor.

  Args:
      monitor_info (str): The text containing monitor information.

  Returns:
      str: The ID of the focused monitor or None if not found.
  """
  current_monitor_id = None
  for line in monitor_info.splitlines():
    # Skip the first line of the monitor information
    if "Monitor" in line:
      current_monitor_id = line.split("\n")[0].split(" ")[3][0]
      continue
    if "focused: yes" in line:
      # Extract the monitor ID from the line preceding "focused: yes"
      monitor_id_line = monitor_info.splitlines()[monitor_info.splitlines().index(line) - 1]
      # Split on whitespace and extract the first element (ID)
      if current_monitor_id:
        return current_monitor_id
      else:
        print("No focused monitor found.")
        
  return None


def main():
  # Get the monitor information using hyprctl monitors
  monitor_info = subprocess.check_output(["hyprctl", "monitors"]).decode("utf-8")

  # Extract the focused monitor ID from the information
  focused_monitor_id = get_focused_monitor(monitor_info)

  # Check if a monitor ID was provided as an argument
  if len(sys.argv) == 2:
    # Call hyprctl focusmonitor with the provided argument
    subprocess.run(["hyprctl", "focusmonitor", sys.argv[1]])
  else:
    # If no argument provided, use the extracted focused monitor ID (if any)
    if focused_monitor_id:
      if focused_monitor_id == "0":
        subprocess.run(["hyprctl", "dispatch", "focusmonitor", "1"])
      else:
        subprocess.run(["hyprctl", "dispatch", "focusmonitor", "0"])
    else:
      print("No focused monitor found or no monitor ID provided.")


if __name__ == "__main__":
  main()
