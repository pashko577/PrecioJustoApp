"""Los comandos (`python -m app...`) deben arrancar al FINAL del archivo.

Si `if __name__ == "__main__": main()` queda antes de una función que `main` usa, al correrlo
como comando falla con NameError, aunque las pruebas que importan el módulo pasen
(incidente del 25-11-2026 con app.export.catalog).
"""

import ast
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "app"


def _is_main_guard(node: ast.stmt) -> bool:
    return (isinstance(node, ast.If) and isinstance(node.test, ast.Compare)
            and isinstance(node.test.left, ast.Name) and node.test.left.id == "__name__")


def test_main_guard_is_the_last_statement():
    offenders = []
    for path in APP.rglob("*.py"):
        body = ast.parse(path.read_text("utf-8")).body
        guards = [i for i, node in enumerate(body) if _is_main_guard(node)]
        if guards and guards[-1] != len(body) - 1:
            offenders.append(str(path.relative_to(APP)))
    assert offenders == []
