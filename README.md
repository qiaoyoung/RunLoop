# RunLoop
最近在整理资料的时候看到了以前写的代码，在此整理下，用到的时候可以方便查看。
对 `RunLoop` 不熟悉的可以查看下[《iOS官方文档》](https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/Multithreading/RunLoopManagement/RunLoopManagement.html#//apple_ref/doc/uid/10000057i-CH16-SW1)和这篇博客[《深入理解RunLoop》](https://blog.ibireme.com/2015/05/18/runloop/)，讲述的淋漓尽致，相信会对你有很大的帮助。
#### 一、使用TableView时出现的问题：
平时开发中绘制 `tableView` 时，我们使用的 `cell` 可能包含很多业务逻辑，比如加载网络图片、绘制内容等等。如果我们不进行优化的话，在绘制 `cell` 时这些任务将同时争夺系统资源，最直接的后果就是页面出现卡顿，更严重的则会 `crash`。
我通过在 `cell` 上加载大的图片（找的系统的壁纸，大小10M左右）并改变其大小来模拟 `cell` 的复杂业务逻辑。

系统的壁纸放在Mac的这个位置：
-> 前往 -> 前往文件夹 `/Library/Desktop Pictures`

`cell` 的绘制方法中实现如下：
```
CGFloat width = (self.view.bounds.size.width-4*kBorder_W) /3;

UIImageView *img1 = [[UIImageView alloc] initWithFrame:CGRectMake(kBorder_W,
kBorder_W,
width,
kCell_H-kBorder_W)];
img1.image = [UIImage imageNamed:@"Blue Pond.jpg"];
[cell addSubview:img1];
UIImageView *img2 = [[UIImageView alloc] initWithFrame:CGRectMake(width+2*kBorder_W,
kBorder_W,
width,
kCell_H-kBorder_W)];
img2.image = [UIImage imageNamed:@"El Capitan 2.jpg"];
[cell addSubview:img2];
UIImageView *img3 = [[UIImageView alloc] initWithFrame:CGRectMake(2*width+3*kBorder_W,
kBorder_W,
width,
kCell_H-kBorder_W)];
img3.image = [UIImage imageNamed:@"El Capitan.jpg"];
[cell addSubview:img3];
```
`tableView` 在绘制 `cell` 的时候同时处理这么多资源，会导致页面滑动不流畅等问题。此处只是模拟，可能效果不明显，但这都不是重点~

**微信对 `cell` 的优化方案是当监听到列表滚动时，停止 `cell` 上的动画等方式，来提升用户体验。**

#### Q：那么问题来了，这个监听是怎么做到的呢？
* 一种是通过 `scrollView` 的 `delegate` 方法;
* 另一种就是通过监听 `runLoop` ；

如果有其他方案，欢迎告知~

### 二、下面就分享下通过监听RunLoop来优化TableView：
步骤如下：
#### （1）.获取当前主线程的 `runloop` 。
```
CFRunLoopRef runloop = CFRunLoopGetCurrent();
```
#### （2）.创建观察者 `CFRunLoopObserverRef` ， 来监听  `runloop` 。
* 创建观察者用到的核心函数就是
`CFRunLoopObserverCreate`：
```
// allocator：该参数为对象内存分配器，一般使用默认的分配器kCFAllocatorDefault。
// activities：要监听runloop的状态
/*
typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {
kCFRunLoopEntry         = (1UL << 0), // 即将进入Loop
kCFRunLoopBeforeTimers  = (1UL << 1), // 即将处理 Timer
kCFRunLoopBeforeSources = (1UL << 2), // 即将处理 Source
kCFRunLoopBeforeWaiting = (1UL << 5), // 即将进入休眠
kCFRunLoopAfterWaiting  = (1UL << 6), // 刚从休眠中唤醒
kCFRunLoopExit          = (1UL << 7), // 即将退出Loop
kCFRunLoopAllActivities = 0x0FFFFFFFU // 所有事件
};
*/
// repeats：是否重复监听
//   order：观察者优先级，当Run Loop中有多个观察者监听同一个运行状态时，根据该优先级判断，0为最高优先级别。
// callout：观察者的回调函数，在Core Foundation框架中用CFRunLoopObserverCallBack重定义了回调函数的闭包。
// context：观察者的上下文。
CF_EXPORT CFRunLoopObserverRef CFRunLoopObserverCreate(CFAllocatorRef allocator,
CFOptionFlags activities,
Boolean repeats,
CFIndex order,
CFRunLoopObserverCallBack callout,
CFRunLoopObserverContext *context);
```
###### a）.创建观察者
```
// 1.定义上下文
CFRunLoopObserverContext context = {
0,
(__bridge void *)(self),
&CFRetain,
&CFRelease,
NULL
};
// 2.定义观察者
static CFRunLoopObserverRef defaultModeObserver;
// 3.创建观察者
defaultModeObserver = CFRunLoopObserverCreate(kCFAllocatorDefault,
kCFRunLoopBeforeWaiting,
YES,
0,
&callBack,
&context);
// 4.给当前runloop添加观察者
// kCFRunLoopDefaultMode: App的默认 Mode，通常主线程是在这个 Mode 下运行的。
// UITrackingRunLoopMode: 界面跟踪 Mode，用于 ScrollView 追踪触摸滑动，保证界面滑动时不受其他 Mode 影响。
// UIInitializationRunLoopMode: 在刚启动 App 时第进入的第一个 Mode，启动完成后就不再使用。
// GSEventReceiveRunLoopMode: 接受系统事件的内部 Mode，通常用不到。
// kCFRunLoopCommonModes: 这是一个占位的 Mode，没有实际作用。
CFRunLoopAddObserver(runloop, defaultModeObserver, kCFRunLoopCommonModes);
// 5.内存管理
CFRelease(defaultModeObserver);
```
###### b）.实现 callBack 函数，只要检测到对应的runloop状态，该函数就会得到响应。
```
static void callBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {

ViewController *vc = (__bridge ViewController *)info;

//无任务  退出
if (vc.tasksArr.count == 0) return;

//从数组中取出任务
runloopBlock block = [vc.tasksArr firstObject];

//执行任务
if (block) {
block();
}

//执行完任务之后移除任务
[vc.tasksArr removeObjectAtIndex:0];

}

```
###### c）.从上面的函数实现中我们看到了block、arr等对象，下面解析下：
* 使用 `Array` 来存储需要执行的任务；
```
- (NSMutableArray *)tasksArr {
if (!_tasksArr) {
_tasksArr = [NSMutableArray array];
}
return _tasksArr;
}
```
* 定义参数 `maxTaskCount` 来表示最大任务数，优化项目；
```
//最大任务数
@property (nonatomic, assign) NSUInteger maxTaskCount;
...
// 当超出最大任务数时，以前的老任务将从数组中移除
self.maxTaskCount = 50;
```
* 使用 `block代码块` 来包装一个个将要执行的任务，便于 `callBack` 函数中分开执行任务，减少同时执行对系统资源的消耗。
```
//1. 定义一个任务block
typedef void(^runloopBlock)();
```
```
//2. 定义一个添加任务的方法，将任务装在数组中
- (void)addTasks:(runloopBlock)task {
//保存新任务
[self.tasksArr addObject:task];
//如果超出最大任务数 丢弃之前的任务
if (self.tasksArr.count > _maxTaskCount) {
[self.tasksArr removeObjectAtIndex:0];
}
}
```
```
//3. 将任务添加到代码块中
// 耗时操作放在任务中
[self addTasks:^{
UIImageView *img1 = [[UIImageView alloc] initWithFrame:CGRectMake(kBorder_W,
kBorder_W,
width,
kCell_H-kBorder_W)];
img1.image = [UIImage imageNamed:@"Blue Pond.jpg"];
[cell addSubview:img1];
}];
[self addTasks:^{
UIImageView *img2 = [[UIImageView alloc] initWithFrame:CGRectMake(width+2*kBorder_W,
kBorder_W,
width,
kCell_H-kBorder_W)];
img2.image = [UIImage imageNamed:@"El Capitan 2.jpg"];
[cell addSubview:img2];
}];
[self addTasks:^{
UIImageView *img3 = [[UIImageView alloc] initWithFrame:CGRectMake(2*width+3*kBorder_W,
kBorder_W,
width,
kCell_H-kBorder_W)];
img3.image = [UIImage imageNamed:@"El Capitan.jpg"];
[cell addSubview:img3];
}];
```
#### （3）.使  `runloop`  不进入休眠状态。
##### Q：按照上面步骤实现的情况下：我有500行的cell，为什么才显示这么一点点呢？
![](https://upload-images.jianshu.io/upload_images/3265534-c18a92fbb80f6e7c.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
##### A：`runloop` 在加载完 `cell` 时没有其他事情做了，为了节省资源消耗，就进入了休眠状态，等待有任务时再次被唤醒。在我们观察者的 `callBack` 函数中任务被一个个取出执行，还没有执行完，`runloop` 就切换状态了（休眠了）， `callBack` 函数不再响应。导致出现上面的情况。

##### 解决方法：
```
创建定时器 (保证runloop回调函数一直在执行)
CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:self
selector:@selector(notDoSomething)];
[displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
...
- (void)notDoSomething {
// 不做事情,就是为了让 callBack() 函数一直相应
}
```
此时，对tableView的优化就大功告成了！


![](https://upload-images.jianshu.io/upload_images/3265534-45f8cc797ee8d2c4.gif?imageMogr2/auto-orient/strip)
