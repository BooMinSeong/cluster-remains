#!/usr/bin/env python3
import sys
import subprocess
import re

def extract_stdout_path(jobid):
    try:
        result = subprocess.run([
            'scontrol', 'show', 'job', str(jobid)
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
        match = re.search(r'StdOut=(\S+)', result.stdout)
        if match:
            return match.group(1)
        else:
            print(f"Could not find StdOut path for job {jobid}", file=sys.stderr)
            sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"Error running scontrol: {e.stderr}", file=sys.stderr)
        sys.exit(1)


def main():
    if len(sys.argv) != 2:
        print(f"Usage: slog [jobid]", file=sys.stderr)
        sys.exit(1)
    jobid = sys.argv[1]
    path = extract_stdout_path(jobid)
    try:
        with open(path, 'r') as f:
            print(f.read())
    except Exception as e:
        print(f"Error reading log file: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

def main_cli():
    main()
