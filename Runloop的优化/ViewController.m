//
//  ViewController.m
//  Runloop的优化
//
//  Created by Joeyoung on 2016/3/29.
//  Copyright © 2016年 Joe. All rights reserved.
//

#import "ViewController.h"
// 任务block
typedef void(^runloopBlock)();

// cell高度
static const CGFloat kCell_H = 150.f;
// cell边框宽度
static const CGFloat kBorder_W = 10.f;


@interface ViewController ()<UITableViewDelegate,UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
// 装任务的Arr
@property (nonatomic, strong) NSMutableArray *tasksArr;
// 最大任务数
@property (nonatomic, assign) NSUInteger maxTaskCount;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 可以自己设置最大任务数量(我这里是当前页面最多同时显示几张照片)
    self.maxTaskCount = 50;
    [self.view addSubview:self.tableView];
    
    // 创建定时器 (保证runloop回调函数一直在执行)
    CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:self
                                                             selector:@selector(notDoSomething)];
    [displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];

    //添加runloop观察者
    [self addRunloopObserver];

}
#pragma mark - ---------------------------------------------------------------
#pragma mark ---- lazy load ----
- (NSMutableArray *)tasksArr {
    if (!_tasksArr) {
        _tasksArr = [NSMutableArray array];
    }
    return _tasksArr;
}
- (UITableView *)tableView {
    if (!_tableView) {
        _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
        _tableView.backgroundColor = [UIColor whiteColor];
        _tableView.tableHeaderView = [UIView new];
        _tableView.tableFooterView = [UIView new];
        _tableView.rowHeight = kCell_H;
        _tableView.delegate =self;
        _tableView.dataSource = self;
    }
    return _tableView;
}
#pragma mark - ---------------------------------------------------------------
#pragma mark ---- tableView delegate,dataSource ----
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 500;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"cellId";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
    }
    
    for (UIView *sub in cell.subviews) {
        if ([sub isMemberOfClass:[UIImageView class]]) {
            [sub removeFromSuperview];
        }
    }
    
    CGFloat width = (self.view.bounds.size.width-4*kBorder_W) /3;
    // 耗时操作可以放在任务中
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
    
    return cell;
}
#pragma mark - ---------------------------------------------------------------
#pragma mark ---- runloop ----
// 添加任务
- (void)addTasks:(runloopBlock)task {
    // 保存新任务
    [self.tasksArr addObject:task];
    // 如果超出最大任务数 丢弃之前的任务
    if (self.tasksArr.count > _maxTaskCount) {
        [self.tasksArr removeObjectAtIndex:0];
    }
}
- (void)notDoSomething {
    // 不做事情,就是为了让 callBack() 函数一直相应
}
// 添加runloop观察者
- (void)addRunloopObserver {
    // 1.获取当前Runloop
    CFRunLoopRef runloop = CFRunLoopGetCurrent();
    
    // 2.创建观察者
    
    // 2.0 定义上下文
    CFRunLoopObserverContext context = {
        0,
        (__bridge void *)(self),
        &CFRetain,
        &CFRelease,
        NULL
    };
    
    // 2.1 定义观察者
    static CFRunLoopObserverRef defaultModeObserver;
    // 2.2 创建观察者
    
//    typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {
//        kCFRunLoopEntry         = (1UL << 0), // 即将进入Loop
//        kCFRunLoopBeforeTimers  = (1UL << 1), // 即将处理 Timer
//        kCFRunLoopBeforeSources = (1UL << 2), // 即将处理 Source
//        kCFRunLoopBeforeWaiting = (1UL << 5), // 即将进入休眠
//        kCFRunLoopAfterWaiting  = (1UL << 6), // 刚从休眠中唤醒
//        kCFRunLoopExit          = (1UL << 7), // 即将退出Loop
//        kCFRunLoopAllActivities = 0x0FFFFFFFU // 所有事件
//    };

    defaultModeObserver = CFRunLoopObserverCreate(kCFAllocatorDefault,
                                                  kCFRunLoopBeforeWaiting,
                                                  YES,
                                                  0,
                                                  &callBack, 
                                                  &context);
   
    // 3. 给当前Runloop添加观察者
    // CFRunLoopMode mode : 设置任务执行的模式
    CFRunLoopAddObserver(runloop, defaultModeObserver, kCFRunLoopCommonModes);
    
    // C中出现 copy,retain,Create等关键字,都需要release
    CFRelease(defaultModeObserver);
}
static void callBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
    
    ViewController *vc = (__bridge ViewController *)info;
    
    // 无任务  退出
    if (vc.tasksArr.count == 0) return;
    
    // 从数组中取出任务
    runloopBlock block = [vc.tasksArr firstObject];
    
    // 执行任务
    if (block) {
        block();
    }
    
    // 执行完任务之后移除任务
    [vc.tasksArr removeObjectAtIndex:0];
    
}

@end
