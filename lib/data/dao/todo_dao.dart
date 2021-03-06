import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:deer/data/dao/in_memory.dart';
import 'package:deer/data/json/todo_json.dart';
import 'package:deer/data/mapper/todo_mapper.dart';
import 'package:deer/domain/entity/todo_entity.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TodoDao {
  Stream<List<TodoEntity>> get all => _data.stream().map((it) => it.toList());

  Stream<List<TodoEntity>> get active => _data.stream().map(
        (it) => it.where((e) => e.status == TodoStatus.active).toList(),
      );

  Stream<List<TodoEntity>> get finished => _data.stream().map(
        (it) => it.where((e) => e.status == TodoStatus.finished).toList(),
      );

  Stream<String> get filter => _filter.stream();

  final _data = InMemory<BuiltList<TodoEntity>>();
  final _filter = InMemory<String>();

  TodoDao() {
    _loadFromDisk();
    _filter.add('All');
    _filter.seedValue = 'All';
  }

  void setFilter(String value) {
    _filter.add(value);
  }

  void _loadFromDisk() async {
    var todosFromDisk = List<TodoEntity>();
    final prefs = await SharedPreferences.getInstance();

    try {
      final data = prefs.getStringList('todos');

      if (data != null) {
        todosFromDisk = data.map((task) {
          final decodedTask = json.decode(task);
          final todoJson = TodoJson.parse(decodedTask);
          return TodoMapper.fromJson(todoJson);
        }).toList();
      }
    } catch (e) {
      print('LoadFromDisk error: $e');
    }

    final list = BuiltList<TodoEntity>(todosFromDisk);
    _data.add(list);
    _data.seedValue = list;
  }

  Future<bool> _saveToDisk() async {
    var result = false;
    final prefs = await SharedPreferences.getInstance();
    final data = _data?.value?.toList();

    try {
      final jsonList = data.map((todo) {
        final todoJson = TodoMapper.toJson(todo);
        final encodedTodo = todoJson.encode();
        return json.encode(encodedTodo);
      }).toList();

      result = await prefs.setStringList('todos', jsonList);
    } catch (e) {
      print('SaveToDisk error: $e');
    }

    return result;
  }

  Future<bool> add(TodoEntity todo) {
    final data = _data.value.toBuilder();
    data.add(todo);
    _data.add(data.build());

    return _saveToDisk();
  }

  Future<bool> remove(TodoEntity todo) {
    final data = _data.value.toBuilder();
    data.remove(todo);
    _data.add(data.build());

    return _saveToDisk();
  }

  Future<bool> update(TodoEntity todo) async {
    if (_data.value == null) {
      return false;
    }

    // addedDate serves as a unique key here
    final current = _data.value.where((it) => it.addedDate.compareTo(todo.addedDate) == 0);
    if (current.isEmpty) {
      return false;
    }

    final data = _data.value.toBuilder();
    data[_data.value.indexOf(current.first)] = todo;
    _data.add(data.build());

    return _saveToDisk();
  }

  Future<bool> clearFinished() {
    final data = _data.value.toBuilder();
    data.removeWhere((e) => e.status == TodoStatus.finished);
    _data.add(data.build());

    return _saveToDisk();
  }

  Future<bool> clearNotifications() async {
    bool cacheDirty = false;
    final data = _data.value.toBuilder();

    data.map((e) {
      final clear = e.notificationDate?.isBefore(DateTime.now()) ?? false;
      if (clear) {
        cacheDirty = true;
        return e.rebuild((b) => b..notificationDate = null);
      } else {
        return e;
      }
    });

    if (cacheDirty) {
      final list = data.build();
      _data.add(list);
      _data.seedValue = list;
      return _saveToDisk();
    } else {
      return false;
    }
  }
}
