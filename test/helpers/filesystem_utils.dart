import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:file/memory.dart';

void copyFileSync(File source, File destination) {
  if (!destination.existsSync()) destination.createSync();
  destination.writeAsBytesSync(source.readAsBytesSync());
}

void copyDirectorySync(Directory source, Directory destination) {
  if (!destination.existsSync()) {
    destination.createSync(recursive: true);
  }
  source.listSync(recursive: false).forEach((entity) {
    if (entity is File) {
      copyFileSync(entity, destination.childFile(entity.basename));
    } else if (entity is Directory) {
      copyDirectorySync(entity, destination.childDirectory(entity.basename));
    }
  });
}

FileSystem setupFileSystem(FileSystem fs) {
  fs.directory('/').delete(recursive: true);

  var base = const LocalFileSystem()
    ..currentDirectory = 'test/resources/filesystem';
  copyDirectorySync(base.currentDirectory, fs.currentDirectory);
/*
  fs.file('/file.txt').createSync();
  fs.directory('/dir').createSync();
  fs.file('/dir/foo.txt').createSync();
  fs.directory('dir/bar').createSync();
  fs.file('dir/bar/foo.txt').createSync();
  fs.file('dir/bar/bar.txt').createSync();
  fs.directory('dir/bar/baz').createSync();*/
  return fs;
}

FileSystem createLocalFileSystem() => setupFileSystem(
      const LocalFileSystem()..currentDirectory = 'test/resources/filesystem',
    );

FileSystem createMemoryFileSystem() => setupFileSystem(MemoryFileSystem());
