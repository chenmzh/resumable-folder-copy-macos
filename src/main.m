#import <Cocoa/Cocoa.h>
#import <signal.h>

static NSString * const SourcesDefaultsKey = @"TransferSources";
static NSString * const DestinationDefaultsKey = @"TransferDestination";

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property NSWindow *window;
@property NSMutableArray<NSString *> *sources;
@property NSString *destination;
@property NSTableView *sourceTable;
@property NSTextField *destinationField;
@property NSTextField *statusLabel;
@property NSTextField *progressLabel;
@property NSProgressIndicator *progressBar;
@property NSButton *chooseSourcesButton;
@property NSButton *removeButton;
@property NSButton *clearButton;
@property NSButton *chooseDestinationButton;
@property NSButton *startButton;
@property NSButton *pauseButton;
@property NSButton *verifyButton;
@property NSTimer *timer;
@end

@implementation AppDelegate

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color {
    NSTextField *field = [NSTextField labelWithString:text];
    field.font = [NSFont systemFontOfSize:size weight:weight];
    field.textColor = color;
    return field;
}

- (NSButton *)button:(NSString *)title action:(SEL)action frame:(NSRect)frame {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.frame = frame;
    return button;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self loadConfiguration];
    [self buildWindow];
    [self refreshStatus];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(refreshStatus) userInfo:nil repeats:YES];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--resume"]) {
        [self performSelector:@selector(resumeAfterLaunch) withObject:nil afterDelay:1.0];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

- (void)loadConfiguration {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSArray *savedSources = [defaults stringArrayForKey:SourcesDefaultsKey];
    NSString *savedDestination = [defaults stringForKey:DestinationDefaultsKey];
    self.sources = savedSources ? [savedSources mutableCopy] : [NSMutableArray array];
    self.destination = savedDestination ?: @"";

}

- (void)saveConfiguration {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:self.sources forKey:SourcesDefaultsKey];
    [defaults setObject:self.destination ?: @"" forKey:DestinationDefaultsKey];
}

- (void)buildWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 820, 650)
                                               styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                 backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"断点续传复制";
    [self.window center];
    NSView *content = self.window.contentView;

    NSTextField *title = [self label:@"断点续传复制" size:25 weight:NSFontWeightSemibold color:NSColor.labelColor];
    title.frame = NSMakeRect(28, 600, 760, 34);
    [content addSubview:title];
    NSTextField *subtitle = [self label:@"选择一个或多个源文件夹，再选择目标目录；每个源文件夹会复制到目标下的同名子目录。" size:13 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    subtitle.frame = NSMakeRect(28, 574, 760, 22);
    [content addSubview:subtitle];

    NSTextField *sourceTitle = [self label:@"源文件夹（支持多选）" size:14 weight:NSFontWeightSemibold color:NSColor.labelColor];
    sourceTitle.frame = NSMakeRect(28, 538, 760, 22);
    [content addSubview:sourceTitle];

    self.sourceTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 750, 130)];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"path"];
    column.title = @"复制任务";
    column.width = 740;
    [self.sourceTable addTableColumn:column];
    self.sourceTable.headerView = nil;
    self.sourceTable.rowHeight = 25;
    self.sourceTable.delegate = self;
    self.sourceTable.dataSource = self;
    self.sourceTable.allowsMultipleSelection = YES;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(28, 395, 764, 135)];
    scroll.documentView = self.sourceTable;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    [content addSubview:scroll];

    self.chooseSourcesButton = [self button:@"选择源文件夹…" action:@selector(chooseSources:) frame:NSMakeRect(28, 354, 140, 32)];
    self.removeButton = [self button:@"移除选中" action:@selector(removeSelectedSources:) frame:NSMakeRect(180, 354, 105, 32)];
    self.clearButton = [self button:@"清空列表" action:@selector(clearSources:) frame:NSMakeRect(297, 354, 100, 32)];
    [content addSubview:self.chooseSourcesButton];
    [content addSubview:self.removeButton];
    [content addSubview:self.clearButton];

    NSTextField *destinationTitle = [self label:@"目标目录" size:14 weight:NSFontWeightSemibold color:NSColor.labelColor];
    destinationTitle.frame = NSMakeRect(28, 316, 100, 22);
    [content addSubview:destinationTitle];
    self.destinationField = [[NSTextField alloc] initWithFrame:NSMakeRect(28, 278, 610, 30)];
    self.destinationField.editable = NO;
    self.destinationField.selectable = YES;
    self.destinationField.stringValue = self.destination ?: @"";
    [content addSubview:self.destinationField];
    self.chooseDestinationButton = [self button:@"选择目标…" action:@selector(chooseDestination:) frame:NSMakeRect(650, 277, 142, 32)];
    [content addSubview:self.chooseDestinationButton];

    self.statusLabel = [self label:@"正在读取状态…" size:17 weight:NSFontWeightMedium color:NSColor.labelColor];
    self.statusLabel.frame = NSMakeRect(28, 232, 764, 28);
    [content addSubview:self.statusLabel];
    self.progressBar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(28, 201, 764, 18)];
    self.progressBar.style = NSProgressIndicatorStyleBar;
    self.progressBar.minValue = 0;
    self.progressBar.maxValue = 100;
    [content addSubview:self.progressBar];
    self.progressLabel = [self label:@"等待开始" size:13 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    self.progressLabel.frame = NSMakeRect(28, 170, 764, 22);
    [content addSubview:self.progressLabel];

    self.startButton = [self button:@"开始 / 继续" action:@selector(startTransfer:) frame:NSMakeRect(28, 120, 125, 34)];
    self.pauseButton = [self button:@"暂停" action:@selector(pauseTransfer:) frame:NSMakeRect(165, 120, 90, 34)];
    self.verifyButton = [self button:@"慢速校验" action:@selector(startVerification:) frame:NSMakeRect(267, 120, 105, 34)];
    NSButton *logButton = [self button:@"打开日志" action:@selector(openLog:) frame:NSMakeRect(384, 120, 100, 34)];
    NSButton *revealButton = [self button:@"显示目标目录" action:@selector(revealDestination:) frame:NSMakeRect(496, 120, 125, 34)];
    for (NSButton *button in @[self.startButton, self.pauseButton, self.verifyButton, logButton, revealButton]) [content addSubview:button];

    NSTextField *note = [self label:@"暂停、断网、关闭 app 或重启后都可继续；未完成文件保存在目标目录。ETA 在文件清单建立完成后出现。" size:12 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor];
    note.frame = NSMakeRect(28, 68, 764, 34);
    note.maximumNumberOfLines = 2;
    [content addSubview:note];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.sources.count; }

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTextField *field = [tableView makeViewWithIdentifier:@"PathCell" owner:self];
    if (!field) {
        field = [NSTextField labelWithString:@""];
        field.identifier = @"PathCell";
        field.lineBreakMode = NSLineBreakByTruncatingMiddle;
        field.selectable = YES;
    }
    field.stringValue = self.sources[row];
    return field;
}

- (void)chooseSources:(id)sender {
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = YES;
    panel.canCreateDirectories = NO;
    panel.prompt = @"添加";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        NSMutableSet *basenames = [NSMutableSet set];
        for (NSString *existing in self.sources) [basenames addObject:existing.lastPathComponent.lowercaseString];
        NSMutableArray *conflicts = [NSMutableArray array];
        for (NSURL *url in panel.URLs) {
            NSString *path = url.path.stringByStandardizingPath;
            if ([self.sources containsObject:path]) continue;
            NSString *basename = path.lastPathComponent.lowercaseString;
            if ([basenames containsObject:basename]) { [conflicts addObject:path.lastPathComponent]; continue; }
            [basenames addObject:basename];
            [self.sources addObject:path];
        }
        [self saveConfiguration];
        [self.sourceTable reloadData];
        [self refreshStatus];
        if (conflicts.count) [self showAlert:[NSString stringWithFormat:@"以下同名目录未添加，以免写入同一个目标：%@", [conflicts componentsJoinedByString:@", "]]];
    }];
}

- (void)removeSelectedSources:(id)sender {
    NSIndexSet *selected = self.sourceTable.selectedRowIndexes;
    [selected enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger idx, BOOL *stop) { [self.sources removeObjectAtIndex:idx]; }];
    [self saveConfiguration];
    [self.sourceTable reloadData];
    [self refreshStatus];
}

- (void)clearSources:(id)sender {
    [self.sources removeAllObjects];
    [self saveConfiguration];
    [self.sourceTable reloadData];
    [self refreshStatus];
}

- (void)chooseDestination:(id)sender {
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.canCreateDirectories = YES;
    panel.prompt = @"选择";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        self.destination = panel.URL.path.stringByStandardizingPath;
        self.destinationField.stringValue = self.destination;
        [self saveConfiguration];
        [self refreshStatus];
    }];
}

- (NSString *)stateRoot { return self.destination.length ? [self.destination stringByAppendingPathComponent:@".cygentig-transfer"] : @""; }

- (NSString *)readText:(NSString *)path {
    if (path.length == 0) return nil;
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (pid_t)activePID {
    pid_t pid = (pid_t)[[self readText:[[self stateRoot] stringByAppendingPathComponent:@"worker.pid"]] intValue];
    return (pid > 1 && kill(pid, 0) == 0) ? pid : 0;
}

- (void)refreshStatus {
    BOOL running = [self activePID] != 0;
    NSString *status = [self readText:[[self stateRoot] stringByAppendingPathComponent:@"status.txt"]];
    if (self.sources.count == 0) self.statusLabel.stringValue = @"请选择至少一个源文件夹";
    else if (self.destination.length == 0) self.statusLabel.stringValue = @"请选择目标目录";
    else if (![NSFileManager.defaultManager fileExistsAtPath:self.destination]) self.statusLabel.stringValue = @"目标目录当前不可用";
    else self.statusLabel.stringValue = status ?: [NSString stringWithFormat:@"就绪：%lu 个复制任务", (unsigned long)self.sources.count];

    NSString *progress = [self readText:[[self stateRoot] stringByAppendingPathComponent:@"progress.txt"]];
    if (running && progress.length) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"([0-9]{1,3})%" options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:progress options:0 range:NSMakeRange(0, progress.length)];
        double percent = (match && match.numberOfRanges > 1) ? [[progress substringWithRange:[match rangeAtIndex:1]] doubleValue] : 0;
        self.progressBar.indeterminate = NO;
        [self.progressBar stopAnimation:nil];
        self.progressBar.doubleValue = percent;
        self.progressLabel.stringValue = progress;
    } else if (running) {
        self.progressBar.indeterminate = YES;
        [self.progressBar startAnimation:nil];
        self.progressLabel.stringValue = @"正在建立文件清单，完成后显示速度和 ETA";
    } else {
        self.progressBar.indeterminate = NO;
        [self.progressBar stopAnimation:nil];
        BOOL complete = [status containsString:@"全部"] || [status containsString:@"通过逐内容校验"];
        self.progressBar.doubleValue = complete ? 100 : 0;
        self.progressLabel.stringValue = complete ? @"100%" : @"等待开始";
    }

    BOOL configurable = !running;
    self.chooseSourcesButton.enabled = configurable;
    self.removeButton.enabled = configurable && self.sourceTable.selectedRowIndexes.count > 0;
    self.clearButton.enabled = configurable && self.sources.count > 0;
    self.chooseDestinationButton.enabled = configurable;
    self.startButton.enabled = configurable && self.sources.count > 0 && self.destination.length > 0;
    self.verifyButton.enabled = self.startButton.enabled;
    self.pauseButton.enabled = running;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification { [self refreshStatus]; }

- (NSString *)configurationError {
    if (self.sources.count == 0) return @"请先选择至少一个源文件夹。";
    if (self.destination.length == 0) return @"请先选择目标目录。";
    if (![NSFileManager.defaultManager fileExistsAtPath:self.destination]) return @"目标目录当前不可用，请确认硬盘已挂载。";
    NSMutableSet *names = [NSMutableSet set];
    for (NSString *source in self.sources) {
        if (![NSFileManager.defaultManager fileExistsAtPath:source]) return [NSString stringWithFormat:@"源目录当前不可用：%@", source];
        NSString *name = source.lastPathComponent.lowercaseString;
        if ([names containsObject:name]) return [NSString stringWithFormat:@"存在同名源目录：%@", source.lastPathComponent];
        [names addObject:name];
        NSString *target = [self.destination stringByAppendingPathComponent:source.lastPathComponent].stringByStandardizingPath;
        NSString *standardSource = source.stringByStandardizingPath;
        if ([target isEqualToString:standardSource] || [target hasPrefix:[standardSource stringByAppendingString:@"/"]]) {
            return [NSString stringWithFormat:@"目标会落在源目录内部，可能造成递归复制：%@", source];
        }
    }
    return nil;
}

- (void)showAlert:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"断点续传复制";
    alert.informativeText = message;
    [alert runModal];
}

- (void)launchWorker:(BOOL)verifyOnly {
    NSString *error = [self configurationError];
    if (error) { [self showAlert:error]; return; }
    NSString *script = [NSBundle.mainBundle pathForResource:@"transfer" ofType:@"zsh"];
    if (!script) { [self showAlert:@"app 内缺少传输组件。"] ; return; }
    NSMutableArray *arguments = [NSMutableArray arrayWithObjects:script, @"--destination", self.destination, nil];
    if (verifyOnly) [arguments addObject:@"--verify-only"];
    for (NSString *source in self.sources) { [arguments addObject:@"--source"]; [arguments addObject:source]; }
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/zsh";
    task.arguments = arguments;
    NSFileHandle *nullHandle = [NSFileHandle fileHandleForWritingAtPath:@"/dev/null"];
    task.standardOutput = nullHandle;
    task.standardError = nullHandle;
    @try {
        [task launch];
        self.statusLabel.stringValue = @"正在启动…";
        [self performSelector:@selector(refreshStatus) withObject:nil afterDelay:0.8];
    } @catch (NSException *exception) {
        [self showAlert:[@"无法启动：" stringByAppendingString:exception.reason ?: @"未知错误"]];
    }
}

- (void)startTransfer:(id)sender { [self launchWorker:NO]; }
- (void)resumeAfterLaunch { [self launchWorker:NO]; }
- (void)startVerification:(id)sender { [self launchWorker:YES]; }

- (void)pauseTransfer:(id)sender {
    pid_t pid = [self activePID];
    if (!pid) { [self refreshStatus]; return; }
    if (kill(pid, SIGTERM) == 0) self.statusLabel.stringValue = @"正在安全暂停…";
    else [self showAlert:@"暂停信号发送失败。"];
}

- (void)openLog:(id)sender {
    if (self.destination.length == 0) { [self showAlert:@"请先选择目标目录。"] ; return; }
    NSString *root = [self stateRoot];
    NSString *path = [root stringByAppendingPathComponent:@"transfer.log"];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) [NSFileManager.defaultManager createFileAtPath:path contents:NSData.data attributes:nil];
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:path]];
}

- (void)revealDestination:(id)sender {
    if (self.destination.length == 0) { [self showAlert:@"请先选择目标目录。"] ; return; }
    [NSWorkspace.sharedWorkspace selectFile:nil inFileViewerRootedAtPath:self.destination];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
