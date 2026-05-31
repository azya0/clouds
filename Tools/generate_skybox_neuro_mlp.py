#!/usr/bin/env python3
"""Generate the statically unrolled MLP used by SkyboxNeuro.gdshader."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
import torch


BEGIN_MARKER = "// BEGIN GENERATED SKYBOX MLP"
END_MARKER = "// END GENERATED SKYBOX MLP"
LEGACY_MARKER = "// 6 x 64"
T_SCALE = 38.0

EXPECTED_SHAPES = {
    "trunk.0.weight": (64, 153),
    "trunk.0.bias": (64,),
    "trunk.2.weight": (64, 64),
    "trunk.2.bias": (64,),
    "trunk.4.weight": (64, 64),
    "trunk.4.bias": (64,),
    "clf_head.weight": (1, 64),
    "clf_head.bias": (1,),
    "reg_head.weight": (1, 64),
    "reg_head.bias": (1,),
}


def glsl_float(value: float) -> str:
    value = float(np.float32(value))
    if not math.isfinite(value):
        raise ValueError(f"Non-finite model value: {value}")
    text = f"{value:.9g}"
    if "e" not in text and "." not in text:
        text += ".0"
    return text


def sh_features_numpy(v: np.ndarray) -> np.ndarray:
    x, y, z = v[:, 0], v[:, 1], v[:, 2]
    out = [np.ones(len(v)) * 0.5 / np.sqrt(np.pi)]
    out += [np.sqrt(3 / (4 * np.pi)) * y, np.sqrt(3 / (4 * np.pi)) * z, np.sqrt(3 / (4 * np.pi)) * x]
    out += [
        0.5 * np.sqrt(15 / np.pi) * x * y,
        0.5 * np.sqrt(15 / np.pi) * y * z,
        0.25 * np.sqrt(5 / np.pi) * (3 * z * z - 1),
        0.5 * np.sqrt(15 / np.pi) * x * z,
        0.25 * np.sqrt(15 / np.pi) * (x * x - y * y),
    ]
    out += [
        0.25 * np.sqrt(35 / (2 * np.pi)) * y * (3 * x * x - y * y),
        0.5 * np.sqrt(105 / np.pi) * x * y * z,
        0.25 * np.sqrt(21 / (2 * np.pi)) * y * (5 * z * z - 1),
        0.25 * np.sqrt(7 / np.pi) * z * (5 * z * z - 3),
        0.25 * np.sqrt(21 / (2 * np.pi)) * x * (5 * z * z - 1),
        0.25 * np.sqrt(105 / np.pi) * z * (x * x - y * y),
        0.25 * np.sqrt(35 / (2 * np.pi)) * x * (x * x - 3 * y * y),
    ]
    out += [
        0.75 * np.sqrt(35 / np.pi) * x * y * (x * x - y * y),
        0.75 * np.sqrt(35 / (2 * np.pi)) * y * z * (3 * x * x - y * y),
        0.75 * np.sqrt(5 / np.pi) * x * y * (7 * z * z - 1),
        0.75 * np.sqrt(5 / (2 * np.pi)) * y * z * (7 * z * z - 3),
        (3 / 16) * np.sqrt(1 / np.pi) * (35 * z**4 - 30 * z * z + 3),
        0.75 * np.sqrt(5 / (2 * np.pi)) * x * z * (7 * z * z - 3),
        (3 / 8) * np.sqrt(5 / np.pi) * (x * x - y * y) * (7 * z * z - 1),
        0.75 * np.sqrt(35 / (2 * np.pi)) * x * z * (x * x - 3 * y * y),
        (3 / 16) * np.sqrt(35 / np.pi) * (x**4 - 6 * x * x * y * y + y**4),
    ]
    return np.column_stack(out).astype(np.float32)


def model_features_numpy(position: np.ndarray, end_point: np.ndarray) -> np.ndarray:
    n_unit = position / np.linalg.norm(position, axis=1, keepdims=True)
    l_unit = end_point / np.linalg.norm(end_point, axis=1, keepdims=True)
    dot_nl = (n_unit * l_unit).sum(axis=1, keepdims=True)
    r_vec = 2 * dot_nl * n_unit - l_unit
    r_unit = r_vec / (np.linalg.norm(r_vec, axis=1, keepdims=True) + 1e-8)
    base = np.hstack([n_unit, l_unit])
    fourier = [base]
    for k in range(6):
        freq = (2.0**k) * np.pi
        fourier += [np.sin(freq * base), np.cos(freq * base)]
    return np.hstack(
        [*fourier, sh_features_numpy(n_unit), sh_features_numpy(l_unit), sh_features_numpy(r_unit)]
    ).astype(np.float32)


def load_state_dict(model_path: Path) -> dict[str, np.ndarray]:
    state = torch.load(model_path, map_location="cpu", weights_only=True)
    actual_shapes = {name: tuple(tensor.shape) for name, tensor in state.items()}
    if actual_shapes != EXPECTED_SHAPES:
        raise ValueError(f"Unexpected state_dict shapes:\n{actual_shapes}")
    parameter_count = sum(tensor.numel() for tensor in state.values())
    if parameter_count != 18306:
        raise ValueError(f"Expected 18306 parameters, got {parameter_count}")
    return {name: tensor.detach().cpu().numpy().astype(np.float32) for name, tensor in state.items()}


def sh_feature_expressions(prefix: str) -> list[str]:
    x, y, z = f"{prefix}.x", f"{prefix}.y", f"{prefix}.z"
    c = glsl_float
    return [
        c(0.5 / np.sqrt(np.pi)),
        f"{c(np.sqrt(3 / (4 * np.pi)))} * {y}",
        f"{c(np.sqrt(3 / (4 * np.pi)))} * {z}",
        f"{c(np.sqrt(3 / (4 * np.pi)))} * {x}",
        f"{c(0.5 * np.sqrt(15 / np.pi))} * {x} * {y}",
        f"{c(0.5 * np.sqrt(15 / np.pi))} * {y} * {z}",
        f"{c(0.25 * np.sqrt(5 / np.pi))} * (3.0 * {z} * {z} - 1.0)",
        f"{c(0.5 * np.sqrt(15 / np.pi))} * {x} * {z}",
        f"{c(0.25 * np.sqrt(15 / np.pi))} * ({x} * {x} - {y} * {y})",
        f"{c(0.25 * np.sqrt(35 / (2 * np.pi)))} * {y} * (3.0 * {x} * {x} - {y} * {y})",
        f"{c(0.5 * np.sqrt(105 / np.pi))} * {x} * {y} * {z}",
        f"{c(0.25 * np.sqrt(21 / (2 * np.pi)))} * {y} * (5.0 * {z} * {z} - 1.0)",
        f"{c(0.25 * np.sqrt(7 / np.pi))} * {z} * (5.0 * {z} * {z} - 3.0)",
        f"{c(0.25 * np.sqrt(21 / (2 * np.pi)))} * {x} * (5.0 * {z} * {z} - 1.0)",
        f"{c(0.25 * np.sqrt(105 / np.pi))} * {z} * ({x} * {x} - {y} * {y})",
        f"{c(0.25 * np.sqrt(35 / (2 * np.pi)))} * {x} * ({x} * {x} - 3.0 * {y} * {y})",
        f"{c(0.75 * np.sqrt(35 / np.pi))} * {x} * {y} * ({x} * {x} - {y} * {y})",
        f"{c(0.75 * np.sqrt(35 / (2 * np.pi)))} * {y} * {z} * (3.0 * {x} * {x} - {y} * {y})",
        f"{c(0.75 * np.sqrt(5 / np.pi))} * {x} * {y} * (7.0 * {z} * {z} - 1.0)",
        f"{c(0.75 * np.sqrt(5 / (2 * np.pi)))} * {y} * {z} * (7.0 * {z} * {z} - 3.0)",
        f"{c((3 / 16) * np.sqrt(1 / np.pi))} * (35.0 * {z} * {z} * {z} * {z} - 30.0 * {z} * {z} + 3.0)",
        f"{c(0.75 * np.sqrt(5 / (2 * np.pi)))} * {x} * {z} * (7.0 * {z} * {z} - 3.0)",
        f"{c((3 / 8) * np.sqrt(5 / np.pi))} * ({x} * {x} - {y} * {y}) * (7.0 * {z} * {z} - 1.0)",
        f"{c(0.75 * np.sqrt(35 / (2 * np.pi)))} * {x} * {z} * ({x} * {x} - 3.0 * {y} * {y})",
        f"{c((3 / 16) * np.sqrt(35 / np.pi))} * ({x} * {x} * {x} * {x} - 6.0 * {x} * {x} * {y} * {y} + {y} * {y} * {y} * {y})",
    ]


def linear_expression(inputs: list[str], weights: np.ndarray, bias: float, indent: str = "\t") -> str:
    parts = [glsl_float(bias)]
    for start in range(0, len(inputs), 4):
        names = inputs[start : start + 4]
        values = weights[start : start + 4]
        while len(names) < 4:
            names.append("0.0")
            values = np.append(values, np.float32(0.0))
        parts.append(
            f"dot(vec4({', '.join(names)}), vec4({', '.join(glsl_float(value) for value in values)}))"
        )
    return ("\n" + indent + "\t+ ").join(parts)


def emit_layer(lines: list[str], name: str, inputs: list[str], weights: np.ndarray, biases: np.ndarray) -> list[str]:
    outputs = [f"{name}_{index}" for index in range(len(biases))]
    for index, output in enumerate(outputs):
        expr = linear_expression(inputs.copy(), weights[index], biases[index])
        lines += [f"\tfloat {output} = max(0.0,", f"\t\t{expr}", "\t);"]
    return outputs


def generate_glsl(state: dict[str, np.ndarray]) -> str:
    lines = [
        BEGIN_MARKER,
        "// Generated by Tools/generate_skybox_neuro_mlp.py. Do not edit by hand.",
        "float skybox_mlp_softplus(float value) {",
        "\treturn max(value, 0.0) + log(1.0 + exp(-abs(value)));",
        "}",
        "",
        "float regressor_layer(vec3 position, vec3 end_point) {",
        "\tvec3 n_unit = normalize(position);",
        "\tvec3 l_unit = normalize(end_point);",
        "\tvec3 r_vec = 2.0 * dot(n_unit, l_unit) * n_unit - l_unit;",
        "\tvec3 r_unit = r_vec / (length(r_vec) + 1e-8);",
    ]
    base = ["n_unit.x", "n_unit.y", "n_unit.z", "l_unit.x", "l_unit.y", "l_unit.z"]
    features = list(base)
    for k in range(6):
        frequency = glsl_float((2.0**k) * np.pi)
        features += [f"sin({frequency} * {value})" for value in base]
        features += [f"cos({frequency} * {value})" for value in base]
    features += sh_feature_expressions("n_unit")
    features += sh_feature_expressions("l_unit")
    features += sh_feature_expressions("r_unit")
    if len(features) != 153:
        raise AssertionError(f"Expected 153 features, got {len(features)}")
    feature_names = [f"feature_{index}" for index in range(len(features))]
    lines += [f"\tfloat {name} = {expression};" for name, expression in zip(feature_names, features)]
    layer_0 = emit_layer(lines, "hidden_0", feature_names, state["trunk.0.weight"], state["trunk.0.bias"])
    layer_1 = emit_layer(lines, "hidden_1", layer_0, state["trunk.2.weight"], state["trunk.2.bias"])
    layer_2 = emit_layer(lines, "hidden_2", layer_1, state["trunk.4.weight"], state["trunk.4.bias"])
    classifier = linear_expression(layer_2.copy(), state["clf_head.weight"][0], state["clf_head.bias"][0])
    regressor = linear_expression(layer_2.copy(), state["reg_head.weight"][0], state["reg_head.bias"][0])
    lines += [
        "\tfloat classifier_logit =",
        f"\t\t{classifier};",
        "\tif (classifier_logit < 0.0) {",
        "\t\treturn 0.0;",
        "\t}",
        "\tfloat regressor_logit =",
        f"\t\t{regressor};",
        f"\treturn skybox_mlp_softplus(regressor_logit) / {glsl_float(T_SCALE)};",
        "}",
        "",
        "float cast_ray_to_sun(vec3 position, float current_time) {",
        "\tvec3 direction = -normalize(light_direction);",
        "\tvec3 end_point = get_sphere_intersection(position, direction);",
        "\treturn regressor_layer(position, end_point);",
        "}",
        END_MARKER,
        "",
    ]
    return "\n".join(lines)


def reference_predict(state: dict[str, np.ndarray], features: np.ndarray) -> np.ndarray:
    hidden = features
    for index in (0, 2, 4):
        hidden = np.maximum(0.0, hidden @ state[f"trunk.{index}.weight"].T + state[f"trunk.{index}.bias"])
    classifier = hidden @ state["clf_head.weight"].T + state["clf_head.bias"]
    regressor = hidden @ state["reg_head.weight"].T + state["reg_head.bias"]
    softplus = np.maximum(regressor, 0.0) + np.log1p(np.exp(-np.abs(regressor)))
    return np.where(classifier >= 0.0, softplus / T_SCALE, 0.0).ravel()


def verify_numpy_equivalence(model_path: Path, state: dict[str, np.ndarray]) -> None:
    rng = np.random.default_rng(20260531)
    position = rng.normal(size=(32, 3)).astype(np.float32)
    position /= np.linalg.norm(position, axis=1, keepdims=True)
    position *= rng.uniform(0.75, 1.0, size=(32, 1)).astype(np.float32)
    direction = rng.normal(size=(32, 3)).astype(np.float32)
    direction /= np.linalg.norm(direction, axis=1, keepdims=True)
    projection = (position * direction).sum(axis=1, keepdims=True)
    end_point = position + direction * (-projection + np.sqrt(projection * projection + 1.0 - (position * position).sum(axis=1, keepdims=True)))
    features = model_features_numpy(position, end_point)

    class MLP(torch.nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.trunk = torch.nn.Sequential(
                torch.nn.Linear(153, 64),
                torch.nn.ReLU(),
                torch.nn.Linear(64, 64),
                torch.nn.ReLU(),
                torch.nn.Linear(64, 64),
                torch.nn.ReLU(),
            )
            self.clf_head = torch.nn.Linear(64, 1)
            self.reg_head = torch.nn.Linear(64, 1)

        def forward(self, value: torch.Tensor) -> torch.Tensor:
            hidden = self.trunk(value)
            classifier = self.clf_head(hidden)
            regressor = torch.nn.functional.softplus(self.reg_head(hidden))
            return torch.where(classifier >= 0.0, regressor / T_SCALE, 0.0).squeeze(-1)

    model = MLP()
    model.load_state_dict(torch.load(model_path, map_location="cpu", weights_only=True))
    model.eval()
    with torch.no_grad():
        expected = model(torch.from_numpy(features)).numpy()
    actual = reference_predict(state, features)
    np.testing.assert_allclose(actual, expected, rtol=2e-5, atol=1e-7)
    print(f"Verified NumPy/PyTorch equivalence on {len(features)} samples")


def update_shader(shader_path: Path, generated: str) -> None:
    source = shader_path.read_text(encoding="utf-8")
    if BEGIN_MARKER in source:
        start = source.index(BEGIN_MARKER)
        end = source.index("uniform float percentage_troposphere", start)
    elif LEGACY_MARKER in source:
        start = source.index(LEGACY_MARKER)
        end = source.index("uniform float percentage_troposphere", start)
    else:
        raise ValueError("Could not find generated or legacy MLP block in shader")
    updated = source[:start] + generated + source[end:]
    shader_path.write_text(updated, encoding="utf-8")
    print(f"Updated {shader_path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--shader", type=Path, required=True)
    args = parser.parse_args()

    state = load_state_dict(args.model)
    print(f"Loaded {sum(value.size for value in state.values())} parameters from {args.model}")
    verify_numpy_equivalence(args.model, state)
    update_shader(args.shader, generate_glsl(state))


if __name__ == "__main__":
    main()
