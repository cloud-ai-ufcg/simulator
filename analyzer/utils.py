def parse_resource_value(value, unit):
    if isinstance(value, str):
        clean_value = value.replace(unit, '').strip()
        if not clean_value:
            return 0
        return int(clean_value)
    elif value is None:
        return 0
    else:
        return int(value)
