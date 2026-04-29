import argparse
from pathlib import Path
import yaml
import datetime

from jinja2 import Environment, FileSystemLoader, select_autoescape

from docs.astro.formatting import (
    channel_format,
    escape_mdx,
    format_choices,
    format_description,
    li,
    link,
)
from docs.astro.keywords import DEFAULT_MODEL, extract_keywords


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

    _templates_dir = Path(__file__).resolve().parent / 'templates'
    env = Environment(
        loader=FileSystemLoader(_templates_dir),
        autoescape=select_autoescape()
    )
    env.filters.update({
        'channel_format': channel_format,
        'link_tool': link,
        'format_li': li,
        'format_choices': format_choices,
        'format_description': format_description,
        'escape_mdx': escape_mdx
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
