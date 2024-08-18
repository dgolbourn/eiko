import time
from datetime import datetime

project = 'Eiko'
author = 'dgolbourn'
copyright = str(datetime.now().year) + ' ' + author
extensions = [
    "myst_parser",
    'sphinxcontrib.plantuml',
    'sphinx_rtd_theme',
]
myst_enable_extensions = [
  'colon_fence',
  'strikethrough',
  'attrs_block',
]
plantuml_output_format = "svg"
html_theme = "sphinx_rtd_theme"
templates_path = ['_templates']
exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store']
html_static_path = ['_static']
