def parse_resource_value(value, unit):
    """Converte string de recurso para inteiro, removendo unidade."""
    return int(value.replace(unit, '')) if isinstance(value, str) else int(value)
