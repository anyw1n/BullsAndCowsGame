import 'dart:io';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;

// Wolfram Mathematica function to deploy Cloud Api Function for words frequency data
// CloudDeploy[APIFunction[{"word1"->"String","word2"->"String","word3"->"String","word4"->"String","word5"->"String","word6"->"String","word7"->"String","word8"->"String","word9"->"String","word10"->"String"},Values[WordFrequencyData[{#word1,#word2,#word3,#word4,#word5,#word6,#word7,#word8,#word9,#word10},"Total",{2000,Now},Language->"Russian",IgnoreCase->True]]&],Permissions->"Public"]
void main(List<String> args) async {
  try {
    switch (args.first) {
      case "separate":
        await wordsSeparator(
          args[1],
          args[2].split(',').map((e) => int.parse(e)),
          args.elementAtOrNull(3),
        );
      case "frequencies":
        await Future.wait(
          args
              .elementAt(1)
              .split(',')
              .map((i) => loadFrequencies(i, args.elementAtOrNull(2))),
        );
      case "load":
        await Future.wait(
          args.elementAt(1).split(',').map(
                (i) => wordsLoader(
                  i,
                  int.parse(args.elementAt(2)),
                  args.elementAtOrNull(3),
                ),
              ),
        );
    }
  } catch (e) {
    print(e);
    print("""

Usage: dart run bin/words_freq_meter.dart [function] [args]
Functions:
    separate <input filename> <length1,length2,...> <output directory>    Separate words by length.
                                                                          Input: file with words each on new line, lengths of words to save.
                                                                          Output: Text files named by words length with words each on new line.

    frequencies <filename1,filename2,...> <output directory>              Loads frequencies of words and sort them. Skip words that already have frequency in output file.
                                                                          Input: filenames with words.
                                                                          Output: Text files with words and their frequencies separated by comma each on new line.

    load <filename1,filename2,...> <words count> <output directory>       Takes N first frequent words and save them in output directory.
""");
  }
}

Future<void> wordsSeparator(
  String filename,
  Iterable<int> lengths,
  String? outputDir,
) async {
  print("Reading file $filename...");
  final words = await File(filename).readAsLines();

  final Map<int, Set<String>> map = {for (final i in lengths) i: {}};

  for (final word in words) {
    if (word.contains("-") ||
        word.length < lengths.min ||
        word.length > lengths.max) {
      continue;
    }

    final chars = word.split('');
    if (chars.length != chars.toSet().length) {
      continue;
    }

    map[word.length]?.add(word);
  }

  for (final MapEntry(key: length, value: words) in map.entries) {
    final output = await Directory(outputDir ?? ".").create(recursive: true);
    await File("${output.path}/$length.txt").writeAsString(words.join('\n'));
  }
  print("Finished.");
}

Future<void> loadFrequencies(String filename, String? outputDir) async {
  print("Reading file $filename...");
  final words = await File(filename).readAsLines();
  final output = await Directory(outputDir ?? ".").create(recursive: true);
  final outputFilename = filename.substring(0, filename.lastIndexOf('.'));
  final freqFile = File('${output.path}/$outputFilename-freq.txt');
  final freq = await freqFile.exists()
      ? (await freqFile.readAsLines()).map((e) => e.split(','))
      : null;

  final Map<String, String> map = {
    for (final [String word, String freq] in freq ?? Iterable.empty())
      word: freq
  };

  final missingWords = words.whereNot((word) => map.containsKey(word));

  for (final slice in missingWords.slices(10)) {
    final args = slice.mapIndexed((i, word) => "word${i + 1}=$word");
    final missingArgs =
        args.length < 10 ? defArgs.slice(args.length) : <String>[];
    final uri = Uri.parse(
      'https://www.wolframcloud.com/obj/693a4278-ecf6-4e94-b929-2db7aeee3f1c?${args.followedBy(missingArgs).join('&')}',
    );
    final response = await http.get(uri);
    if (response.statusCode case < 200 || >= 300) {
      print("Invalid status code ${response.body}");
      break;
    }
    final frequencies =
        response.body.replaceAll(RegExp(r'[{}]'), '').split(', ');
    map.addAll({for (final (i, word) in slice.indexed) word: frequencies[i]});
  }

  final sorted = map
      .map((key, value) =>
          MapEntry(key, double.tryParse(value.replaceAll('*^', 'e')) ?? 0))
      .entries
      .sorted((a, b) => b.value.compareTo(a.value));
  var buf = "";
  for (final MapEntry(key: word, value: frequency) in sorted) {
    buf += "$word,$frequency\n";
  }

  await freqFile.writeAsString(buf);
  print("File $outputFilename finished");
}

Future<void> wordsLoader(
  String filename,
  int wordsCount,
  String? outputDir,
) async {
  final words = await File(filename).readAsLines();

  final output = await Directory(outputDir ?? ".").create(recursive: true);
  await File("${output.path}/${words.first.length}.txt").writeAsString(
      words.take(wordsCount).map((e) => e.split(',').first).join('\n'));
}

final defArgs = [
  "word1=word",
  "word2=word",
  "word3=word",
  "word4=word",
  "word5=word",
  "word6=word",
  "word7=word",
  "word8=word",
  "word9=word",
  "word10=word",
];
