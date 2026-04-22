"""
LLM-powered keyword extraction for nf-neuro documentation.

Uses Ollama with the qwen3 model to generate additional relevant keywords
from meta.yml data, improving discoverability on the website and in search
engines.
"""

import json
import logging
import re

log = logging.getLogger(__name__)

DEFAULT_MODEL = "qwen3"


def _build_prompt(data):
    """Build a keyword-extraction prompt from meta.yml data."""
    name = data.get("name", "")
    description = data.get("description", "")
    existing_keywords = data.get("keywords", [])
    tools = data.get("tools", [])

    tool_names = []
    tool_descriptions = []
    for tool in tools:
        for tool_name, tool_meta in tool.items():
            tool_names.append(tool_name)
            if isinstance(tool_meta, dict) and "description" in tool_meta:
                tool_descriptions.append(
                    f"{tool_name}: {tool_meta['description'].strip()}"
                )

    prompt = (
        "You are a scientific SEO expert specialising in neuroimaging and "
        "bioinformatics software.\n\n"
        "Given the following information about a Nextflow module for neuroimaging "
        "data processing, extract a list of relevant keywords for SEO and search "
        "discoverability. Focus on technical terms, neuroimaging concepts, "
        "computational methods, data types, and scientific domains relevant to "
        "the module.\n\n"
        f"Module name: {name}\n"
        f"Description: {description}\n"
        f"Existing keywords: {', '.join(existing_keywords)}\n"
        f"Tools used: {', '.join(tool_names)}\n"
        f"Tool descriptions: {'; '.join(tool_descriptions)}\n\n"
        "Return ONLY a JSON array of 5 to 15 additional keyword strings that are "
        "NOT already present in the existing keywords list. Keywords should be "
        "specific, relevant, and useful for search engines. Do not include "
        "explanations or any other text outside the JSON array.\n\n"
        'Example format: ["keyword1", "keyword2", "keyword3"]'
    )
    return prompt


def extract_keywords(data, model=DEFAULT_MODEL):
    """Extract additional keywords from meta.yml data using an LLM via Ollama.

    Calls the specified Ollama model to generate SEO-relevant keywords that
    complement the existing ones defined in the meta.yml file. Falls back to
    the original keyword list gracefully when Ollama is unavailable or the
    model call fails.

    Parameters
    ----------
    data : dict
        Parsed meta.yml data.
    model : str, optional
        Ollama model name to use for keyword extraction (default: ``qwen3``).

    Returns
    -------
    list[str]
        Augmented list of keywords combining the original entries with any
        additional ones produced by the LLM, deduplicated and in order.
    """
    existing_keywords = data.get("keywords", []) or []

    try:
        import ollama
    except ImportError:
        log.warning(
            "The 'ollama' package is not installed; skipping LLM keyword extraction."
        )
        return existing_keywords

    prompt = _build_prompt(data)

    try:
        response = ollama.chat(
            model=model,
            messages=[{"role": "user", "content": prompt}],
            options={"temperature": 0.2},
        )
        content = response.message.content.strip()

        # The model may wrap the array in markdown fences or add thinking text;
        # extract the first JSON array found in the response.
        match = re.search(r"\[.*?\]", content, re.DOTALL)
        if match:
            new_keywords = json.loads(match.group())
            if isinstance(new_keywords, list):
                existing_lower = {k.lower() for k in existing_keywords}
                additional = [
                    k
                    for k in new_keywords
                    if isinstance(k, str) and k.lower() not in existing_lower
                ]
                return existing_keywords + additional

        log.warning(
            "LLM response did not contain a parseable JSON keyword array; "
            "using original keywords."
        )
    except Exception as exc:
        log.warning("LLM keyword extraction failed (%s); using original keywords.", exc)

    return existing_keywords
