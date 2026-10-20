"""Offline score compiler contract checks; no FPGA tools are invoked."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('compile_score',ROOT/'scripts/compile_score.py')
compiler=importlib.util.module_from_spec(spec);spec.loader.exec_module(compiler)

class ScoreCompilerTest(unittest.TestCase):
    def test_checked_in_roms_reproduce(self):
        for stem,depth in [('src/scores/twinkle',512),('sim/data/score_player_test',16)]:
            with self.subTest(stem=stem):
                words,stats=compiler.compile_text((ROOT/(stem+'.txt')).read_text(encoding='utf8'),depth)
                self.assertEqual(''.join(f'{w:016x}\n' for w in words),(ROOT/(stem+'.hex')).read_text(encoding='ascii'))
                self.assertLessEqual(stats['words'],depth)

    def test_default_score_has_keyboard_pitch_identities(self):
        words,stats=compiler.compile_text((ROOT/'src/scores/twinkle.txt').read_text(encoding='utf8'))
        expected=[60,60,67,67,69,69,67,65,65,64,64,62,62,60,
                  67,67,65,65,64,64,62,67,67,65,65,64,64,62,
                  60,60,67,67,69,69,67,65,65,64,64,62,62,60]
        ons=[w for w in words if w>>60==2]
        self.assertEqual(stats['notes'],42)
        self.assertEqual(stats['events'],84)
        self.assertEqual([w>>34&127 for w in ons],expected)
        self.assertTrue(all(w>>32&3==0 for w in ons))

    def test_note_names_and_independent_a4(self):
        self.assertEqual([compiler.pitch_number(x) for x in ['C4','F#4','Gb4','Bb3','69']], [60,66,66,58,69])
        words,stats=compiler.compile_text('0 1/4 127:A4:reed\nend 1/4\n',8)
        self.assertEqual(words[0],(2<<60)|(127<<34)|(2<<32)|0x0258bf26)
        self.assertEqual(words[1],(1<<60)|1)
        self.assertEqual(words[2],(3<<60)|(127<<34)|(2<<32)|0x0258bf26)
        self.assertEqual(words[3:], [0]*5)
        self.assertEqual(stats['events'],2)

    def test_simultaneous_release_before_new_note(self):
        words,_=compiler.compile_text('1/4 1/4 5:C4:sine\n1/2 1/4 5:D4:flute\nend 1\n',16)
        self.assertEqual([(w>>60) for w in words[:9]],[1,2,1,3,2,1,3,1,0])

    def test_empty_score_is_valid(self):
        self.assertEqual(compiler.compile_text('end 0\n',1)[0],[0])

    def test_invalid_source_is_rejected(self):
        invalid=['0 1/4 0:C4:sine\n', 'end 0\nend 0\n',
                 '0 0 0:C4:sine\nend 1\n', '0 1/3 0:C4:sine\nend 1\n',
                 '-1 1 0:C4:sine\nend 1\n', '0 1 128:C4:sine\nend 1\n',
                 '0 1 0:H4:sine\nend 1\n', '0 1 0:128:sine\nend 1\n',
                 '0 1 0:C4:3\nend 1\n', '0 1 0:C4:sine 0:E4:sine\nend 1\n',
                 '0 1 0:C4:sine\n1/2 1 0:D4:sine\nend 2\n',
                 '0 1 0:C4:sine\nend 1/2\n', '0 1 0:C4\nend 1\n',
                 '0 1/0 0:C4:sine\nend 1\n']
        for source in invalid:
            with self.subTest(source=source):
                with self.assertRaises(ValueError): compiler.compile_text(source)
        with self.assertRaises(ValueError): compiler.compile_text('0 1 0:C4:sine\nend 1\n',2)
        with self.assertRaises(ValueError): compiler.compile_text('end 0\n',0)

    def test_bad_conversion_preserves_existing_rom(self):
        with tempfile.TemporaryDirectory() as directory:
            source=Path(directory)/'bad.txt';output=Path(directory)/'existing.hex'
            source.write_text('0 0 0:C4:sine\nend 0\n',encoding='utf8')
            output.write_bytes(b'unchanged\n')
            run=subprocess.run([sys.executable,str(ROOT/'scripts/compile_score.py'),str(source),str(output)],capture_output=True)
            self.assertEqual(run.returncode,2)
            self.assertEqual(output.read_bytes(),b'unchanged\n')

if __name__=='__main__':unittest.main(verbosity=2)
