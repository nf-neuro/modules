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
    format_map_entries,
    link,
    sanitize_outside_codeblocks,
)
from docs.astro.keywords import DEFAULT_MODEL, extract_keywords


DOC_URL_BASE = "https://nf-neuro.github.io"


def channel_description_format(content):
    """Format channel descriptions for subworkflow tables.

    Splits on ``Structure:`` lines to format the structure separately,
    then sanitises the result for safe MDX rendering.
    """
    _cell = ""
    _descr = content["description"].split("\n")

    try:
        # First check if a structure element defines a list for the structure content.
        if "structure" in content:
            _header = channel_format(content["structure"], heading="Structure")

            _structure = []
            for it in content["structure"]:
                _name, _content = next(iter(it.items()))
                _structure.append(f"<li>**{_name}** [{_content['type']}] {format_description(_content['description'])}</li>")

            _structure = _header + "<br /><ul>" + "".join(_structure) + "</ul>"

        # Else, try to extract the structure line from the description element (legacy),
        # or fallback to formatting the whole description.
        else:
            _structure = next(filter(lambda x: "Structure:" in x, _descr))
            _descr.remove(_structure)
            _structure = _structure.replace('[', '`[', 1)[::-1].replace(']', '`]', 1)[::-1]
            _structure = sanitize_outside_codeblocks(_structure, table_cell=True)

        _cell = "{}<br />{}".format(format_description('\n'.join(_descr)), _structure)
    except StopIteration:
        _cell = format_description("\n".join(_descr))

    if content["type"].lower() == "map" and "entries" in content:
        _cell += "<br />{}".format(format_map_entries(content["entries"]))

    return _cell


def component_format(component):
    ctype = "module" if "/" in component else "subworkflow"
    return f"[{component}]({DOC_URL_BASE}/api/{ctype}s/{component})"


def _create_parser():
    p = argparse.ArgumentParser(
            description='Generate subworkflow markdown from template',
            formatter_class=argparse.RawTextHelpFormatter)

    p.add_argument('subworkflow_path', help='Name of the subworkflow')
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
        'component_format': component_format,
        'link_tool': link,
        'channel_description': channel_description_format,
        'format_choices': format_choices,
        'format_description': format_description,
        'escape_mdx': escape_mdx
    })

    with open(f"{args.subworkflow_path}/meta.yml", "r") as f:
        data = yaml.safe_load(f)

    data["currentcommit"] = args.current_commit_sha
    data["currentdate"] = datetime.datetime.now().strftime("%Y-%m-%d")

    if args.enhance_keywords:
        data["keywords"] = extract_keywords(data, model=args.llm_model)

    template = env.get_template('subworkflow.md.jinja2')
    output_path = Path(args.output)
    output_path.write_text(template.render(**data))


if __name__ == "__main__":
    main()
