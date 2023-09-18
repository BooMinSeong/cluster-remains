from setuptools import setup, find_packages
setup(
    name = "sremain",
    version = "0.2",
    packages = find_packages(),
    entry_points = {
        'console_scripts': [
            'sremain = sremain:main',
            'scrime = scrime:main',
        ],
    }
)