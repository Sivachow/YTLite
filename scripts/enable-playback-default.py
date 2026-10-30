"""Default the documented YTUHD workaround on, retaining its settings toggle."""
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
old = 'return [[NSUserDefaults standardUserDefaults] boolForKey:FixPlaybackKey];'
new = '''NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:FixPlaybackKey] == nil) return YES;
    return [defaults boolForKey:FixPlaybackKey];'''
assert source.count(old) == 1, "Unexpected YTUHD settings; refusing patch"
path.write_text(source.replace(old, new))
