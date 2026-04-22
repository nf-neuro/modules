import argparse
from pathlib import Path
import yaml
import datetime

from jinja2 import Environment, FileSystemLoader, select_autoescape

from keywords import DEFAULT_MODEL, extract_keywords


TYPE_TO_NTYPE = {
    "map": "val",
    "file": "path",
    "string": "val",
    "list": "val",
    "directory": "path",
    "integer": "val",
    "float": "val",
    "boolean": "val"
}


def li(text):
    return f"- {str(text)}"


def link(text, url=None):
    if not url:
        return text
    return f"[{text}]({url})"


def format_choices(choices):
    if isinstance(choices, str):
        choices = [c.strip() for c in choices.split(",")]

    return "<br />".join([li(c) for c in choices]) if choices else ""


def channel_format(_input):
    if isinstance(_input, list):
        def _nametype(_name, _meta):
            return f"{TYPE_TO_NTYPE[_meta['type']]}({_name})"

        return "**Format :** `tuple {format}`".format(
            format=', '.join([_nametype(*next(iter(field.items()))) for field in _input])
        )
    elif isinstance(_input, dict):
        name, meta = next(iter(_input.items()))
        return f"**Format :** `{TYPE_TO_NTYPE[meta['type']]}({name})`"
    else:
        raise ValueError("Input must be a list or a dict")


def _create_parser():
    p = argparse.ArgumentParser(
            description='Generate module markdown from template',
            formatter_class=argparse.RawTextHelpFormatter)

    p.add_argument('module_path', help='Path to the module')
    p.add_argument('current_commit_sha', help='Current commit sha')
    p.add_argument('output', help='Name of the output markdown file')
    p.add_argument(
        '--enhance-keywords', action='store_true', default=False,
        help='Use an LLM via Ollama to extract additional SEO keywords'
    )
    p.add_argument(
        '--llm-model', default=DEFAULT_MODEL, metavar='MODEL',
        help=f'Ollama model used for keyword extraction (default: {DEFAULT_MODEL})'
    )

    return p


def main():
    parser = _create_parser()
    args = parser.parse_args()

    env = Environment(
        loader=FileSystemLoader('docs/astro/templates'),
        autoescape=select_autoescape()
    )
    env.filters.update({
        'channel_format': channel_format,
        'link_tool': link,
        'format_li': li,
        'format_choices': format_choices
    })

    with open(f"{args.module_path}/meta.yml", "r") as f:
        data = yaml.safe_load(f)

    data["currentcommit"] = args.current_commit_sha
    data["currentdate"] = datetime.datetime.now().strftime("%Y-%m-%d")

    if args.enhance_keywords:
        data["keywords"] = extract_keywords(data, model=args.llm_model)

    template = env.get_template('module.md.jinja2')
    output_path = Path(args.output)
    output_path.write_text(template.render(**data))


if __name__ == "__main__":
    main()
