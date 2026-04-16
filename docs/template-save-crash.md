# 模板保存崩溃说明

## 现象

点击“保存模板”后，界面短暂出现红色错误页：

```text
package:flutter/src/widgets/framework.dart: Failed assertion: line 6171 pos 14:
'_dependents.isEmpty': is not true.
```

随后页面又自动恢复。

## 原因

旧实现使用 `showDialog + AlertDialog + 外部 TextEditingController`。

流程大致是：

1. 设置页创建 `TextEditingController`
2. `showDialog` 打开 `AlertDialog`
3. 弹窗内 `TextField` 依赖该 controller 和弹窗上下文
4. 点击保存后 `Navigator.pop`
5. 弹窗路由正在销毁时，外部代码立即 `dispose controller`、`setState`，并曾触发自定义 overlay toast

这个时机容易让 Flutter 在销毁 `InheritedElement` 时发现仍有 dependent 没有清理完，于是触发：

```text
_dependents.isEmpty
```

这不是数据损坏，也不是模板内容错误，而是弹窗生命周期与外部状态更新/资源释放时机冲突。

## 修复方式

已改为自定义底部弹窗 `_TemplateNameSheet`：

- 不再使用 `AlertDialog`
- `TextEditingController` 由弹窗组件自己创建
- `TextEditingController` 由弹窗组件自己释放
- 父页面只接收最终输入结果
- 保存成功提示改为安全的 `SnackBar`

新流程：

```text
设置页 -> showModalBottomSheet -> _TemplateNameSheet
_TemplateNameSheet 自己管理输入框
点击保存 -> pop(name)
设置页拿到 name -> setState 保存模板
```

## 防回归测试

已新增 widget test：

```text
settings can save a template without lifecycle crash
```

测试会真实执行：

1. 打开首页
2. 进入设置
3. 滚动到模板保存按钮
4. 点击保存模板
5. 输入模板名
6. 点击保存
7. 验证成功提示出现

运行：

```bash
flutter test
```
