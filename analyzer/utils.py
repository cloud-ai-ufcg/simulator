def parse_resource_value(value, unit):
    """
    Parse a Kubernetes-style resource quantity into a plain int.

    Args:
        value: Raw value, e.g. "4000m" or "8192Mi" (str), an already
            numeric value, or None.
        unit: Unit suffix to strip when value is a string (e.g. 'm', 'Mi').

    Returns:
        The numeric value with the unit suffix removed, as an int.
        Returns 0 for None or an empty string after stripping the unit.
    """
    if isinstance(value, str):
        clean_value = value.replace(unit, '').strip()
        if not clean_value:
            return 0
        return int(clean_value)
    elif value is None:
        return 0
    else:
        return int(value)
