import subprocess
import re

# Define your mappings here as tuples of (main_brightness, secondary_brightness)
mappings = [(0, 0), (16, 35), (43, 88), (121, 138), (249, 200)]


def get_main_brightness():
    # Use xrandr to get the current brightness
    result = subprocess.run(["xrandr", "--verbose"], stdout=subprocess.PIPE)
    output = result.stdout.decode()

    # Extract the brightness value using regex
    brightness_match = re.search(r"Brightness: (\d\.\d+)", output)
    if brightness_match:
        # Get the brightness from brightnessctl now
        result = subprocess.run(["brightnessctl", "g"], stdout=subprocess.PIPE)
        output = result.stdout.decode()
        return float(brightness_match.group(1)) * 100 + float(
            output
        )  # Convert to percentage

    else:
        raise ValueError("Could not find brightness in xrandr output")


def interpolate(x, x0, y0, x1, y1):
    # Perform linear interpolation
    return y0 + (y1 - y0) * ((x - x0) / (x1 - x0))


def find_closest_mappings(x, mappings):
    lower = None
    upper = None
    for mx, my in mappings:
        if mx <= x:
            lower = (mx, my)
        elif mx > x and upper is None:
            upper = (mx, my)
            break
    return lower, upper


def set_secondary_brightness(brightness):
    # Use ddcutil to set the brightness

    if brightness <= 100:
        subprocess.run(
            [
                "xrandr",
                "--output",
                "DisplayPort-0",
                "--brightness",
                str(brightness / 100),
            ]
        )
        subprocess.run(["ddcutil", "setvcp", "10", "1"])
        return

    subprocess.run(["xrandr", "--output", "DisplayPort-0", "--brightness", "1"])
    brightness -= 100

    subprocess.run(["ddcutil", "setvcp", "10", str(int(brightness))])


def main():
    main_brightness = get_main_brightness()
    print(f"Main monitor brightness is {main_brightness}")
    lower, upper = find_closest_mappings(main_brightness, mappings)

    if lower and upper:
        secondary_brightness = interpolate(main_brightness, *lower, *upper)
    elif lower:
        secondary_brightness = lower[1]
    elif upper:
        secondary_brightness = upper[1]
    else:
        secondary_brightness = main_brightness  # Default if no mappings

    set_secondary_brightness(secondary_brightness)
    print(f"Secondary monitor brightness set to {secondary_brightness}")


if __name__ == "__main__":
    main()
