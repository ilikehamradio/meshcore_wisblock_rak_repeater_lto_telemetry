#!/usr/bin/env python3
"""Map a MeshCore PlatformIO environment to its variant platformio.ini."""
import sys

_VARIANT_PREFIXES = (
    ("RAK_3401", "variants/rak3401/platformio.ini"),
    ("RAK_4631", "variants/rak4631/platformio.ini"),
)


def variant_ini_for_env(env_name):
    """Return the variant platformio.ini path for a MeshCore env name.

    Raises ValueError when the environment is not a supported WisBlock target.
    """
    if not env_name:
        raise ValueError("ENV_NAME is empty.")
    for prefix, path in _VARIANT_PREFIXES:
        if env_name == prefix or env_name.startswith(prefix + "_"):
            return path
    raise ValueError(
        "Unsupported MeshCore environment %r. "
        "Expected a RAK_4631_* or RAK_3401_* env." % (env_name,)
    )


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("Usage: variant_ini.py <ENV_NAME>\n")
        return 2
    try:
        sys.stdout.write(variant_ini_for_env(argv[1]) + "\n")
    except ValueError as exc:
        sys.stderr.write("Error: %s\n" % exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
