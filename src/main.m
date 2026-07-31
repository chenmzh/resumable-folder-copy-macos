#import <Cocoa/Cocoa.h>
#import <signal.h>

static NSString * const SourcesDefaultsKey = @"TransferSources";
static NSString * const DestinationDefaultsKey = @"TransferDestination";
static NSString * const LanguageDefaultsKey = @"InterfaceLanguage";

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property NSWindow *window;
@property NSMutableArray<NSString *> *sources;
@property NSString *destination;
@property NSString *languageCode;
@property NSBundle *localizationBundle;
@property NSTableView *sourceTable;
@property NSTextField *destinationField;
@property NSTextField *titleLabel;
@property NSTextField *subtitleLabel;
@property NSTextField *sourceTitleLabel;
@property NSTextField *destinationTitleLabel;
@property NSTextField *noteLabel;
@property NSTextField *languageLabel;
@property NSTextField *statusLabel;
@property NSTextField *progressLabel;
@property NSProgressIndicator *progressBar;
@property NSPopUpButton *languagePopup;
@property NSButton *chooseSourcesButton;
@property NSButton *removeButton;
@property NSButton *clearButton;
@property NSButton *chooseDestinationButton;
@property NSButton *startButton;
@property NSButton *pauseButton;
@property NSButton *verifyButton;
@property NSButton *logButton;
@property NSButton *revealButton;
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
    self.languageCode = [defaults stringForKey:LanguageDefaultsKey] ?: @"en";
    [self loadLocalizationBundle];

}

- (NSArray<NSDictionary *> *)languageOptions {
    return @[
        @{@"code": @"en", @"name": @"English"},
        @{@"code": @"zh-Hans", @"name": @"中文"},
        @{@"code": @"de", @"name": @"Deutsch"},
        @{@"code": @"fr", @"name": @"Français"},
        @{@"code": @"it", @"name": @"Italiano"},
        @{@"code": @"es", @"name": @"Español"},
        @{@"code": @"pt", @"name": @"Português"},
        @{@"code": @"ja", @"name": @"日本語"},
        @{@"code": @"ko", @"name": @"한국어"},
        @{@"code": @"ar", @"name": @"العربية"}
    ];
}

- (void)loadLocalizationBundle {
    NSString *path = [NSBundle.mainBundle pathForResource:self.languageCode ofType:@"lproj"];
    if (!path) path = [NSBundle.mainBundle pathForResource:@"en" ofType:@"lproj"];
    self.localizationBundle = path ? [NSBundle bundleWithPath:path] : NSBundle.mainBundle;
}

- (NSString *)L:(NSString *)key {
    return [self.localizationBundle localizedStringForKey:key value:key table:@"Localizable"];
}

- (void)updateLocalizedTexts {
    self.window.contentView.userInterfaceLayoutDirection = [self.languageCode isEqualToString:@"ar"] ? NSUserInterfaceLayoutDirectionRightToLeft : NSUserInterfaceLayoutDirectionLeftToRight;
    self.window.title = [self L:@"app_title"];
    self.titleLabel.stringValue = [self L:@"app_title"];
    self.subtitleLabel.stringValue = [self L:@"subtitle"];
    self.sourceTitleLabel.stringValue = [self L:@"source_title"];
    self.destinationTitleLabel.stringValue = [self L:@"destination_title"];
    self.languageLabel.stringValue = [self L:@"language_label"];
    self.chooseSourcesButton.title = [self L:@"choose_sources"];
    self.removeButton.title = [self L:@"remove_selected"];
    self.clearButton.title = [self L:@"clear_list"];
    self.chooseDestinationButton.title = [self L:@"choose_destination"];
    self.startButton.title = [self L:@"start_resume"];
    self.pauseButton.title = [self L:@"pause"];
    self.verifyButton.title = [self L:@"verify"];
    self.logButton.title = [self L:@"open_log"];
    self.revealButton.title = [self L:@"show_destination"];
    self.noteLabel.stringValue = [self L:@"note"];
}

- (void)changeLanguage:(id)sender {
    NSString *selectedCode = self.languagePopup.selectedItem.representedObject;
    if (!selectedCode.length) return;
    self.languageCode = selectedCode;
    [NSUserDefaults.standardUserDefaults setObject:selectedCode forKey:LanguageDefaultsKey];
    [self loadLocalizationBundle];
    [self updateLocalizedTexts];
    [self refreshStatus];
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
    self.window.title = [self L:@"app_title"];
    [self.window center];
    NSView *content = self.window.contentView;

    self.titleLabel = [self label:[self L:@"app_title"] size:25 weight:NSFontWeightSemibold color:NSColor.labelColor];
    self.titleLabel.frame = NSMakeRect(28, 600, 500, 34);
    [content addSubview:self.titleLabel];
    self.languageLabel = [self label:[self L:@"language_label"] size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    self.languageLabel.alignment = NSTextAlignmentRight;
    self.languageLabel.frame = NSMakeRect(540, 607, 90, 22);
    [content addSubview:self.languageLabel];
    self.languagePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(640, 600, 152, 30) pullsDown:NO];
    self.languagePopup.target = self;
    self.languagePopup.action = @selector(changeLanguage:);
    for (NSDictionary *option in [self languageOptions]) {
        [self.languagePopup addItemWithTitle:option[@"name"]];
        self.languagePopup.lastItem.representedObject = option[@"code"];
        if ([option[@"code"] isEqualToString:self.languageCode]) [self.languagePopup selectItem:self.languagePopup.lastItem];
    }
    [content addSubview:self.languagePopup];
    self.subtitleLabel = [self label:[self L:@"subtitle"] size:13 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    self.subtitleLabel.frame = NSMakeRect(28, 574, 764, 22);
    [content addSubview:self.subtitleLabel];

    self.sourceTitleLabel = [self label:[self L:@"source_title"] size:14 weight:NSFontWeightSemibold color:NSColor.labelColor];
    self.sourceTitleLabel.frame = NSMakeRect(28, 538, 760, 22);
    [content addSubview:self.sourceTitleLabel];

    self.sourceTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 750, 130)];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"path"];
    column.title = [self L:@"task_column"];
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

    self.chooseSourcesButton = [self button:[self L:@"choose_sources"] action:@selector(chooseSources:) frame:NSMakeRect(28, 354, 150, 32)];
    self.removeButton = [self button:[self L:@"remove_selected"] action:@selector(removeSelectedSources:) frame:NSMakeRect(190, 354, 120, 32)];
    self.clearButton = [self button:[self L:@"clear_list"] action:@selector(clearSources:) frame:NSMakeRect(322, 354, 110, 32)];
    [content addSubview:self.chooseSourcesButton];
    [content addSubview:self.removeButton];
    [content addSubview:self.clearButton];

    self.destinationTitleLabel = [self label:[self L:@"destination_title"] size:14 weight:NSFontWeightSemibold color:NSColor.labelColor];
    self.destinationTitleLabel.frame = NSMakeRect(28, 316, 300, 22);
    [content addSubview:self.destinationTitleLabel];
    self.destinationField = [[NSTextField alloc] initWithFrame:NSMakeRect(28, 278, 610, 30)];
    self.destinationField.editable = NO;
    self.destinationField.selectable = YES;
    self.destinationField.stringValue = self.destination ?: @"";
    [content addSubview:self.destinationField];
    self.chooseDestinationButton = [self button:[self L:@"choose_destination"] action:@selector(chooseDestination:) frame:NSMakeRect(650, 277, 142, 32)];
    [content addSubview:self.chooseDestinationButton];

    self.statusLabel = [self label:[self L:@"status_loading"] size:17 weight:NSFontWeightMedium color:NSColor.labelColor];
    self.statusLabel.frame = NSMakeRect(28, 232, 764, 28);
    [content addSubview:self.statusLabel];
    self.progressBar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(28, 201, 764, 18)];
    self.progressBar.style = NSProgressIndicatorStyleBar;
    self.progressBar.minValue = 0;
    self.progressBar.maxValue = 100;
    [content addSubview:self.progressBar];
    self.progressLabel = [self label:[self L:@"progress_waiting"] size:13 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    self.progressLabel.frame = NSMakeRect(28, 170, 764, 22);
    [content addSubview:self.progressLabel];

    self.startButton = [self button:[self L:@"start_resume"] action:@selector(startTransfer:) frame:NSMakeRect(28, 120, 135, 34)];
    self.pauseButton = [self button:[self L:@"pause"] action:@selector(pauseTransfer:) frame:NSMakeRect(175, 120, 95, 34)];
    self.verifyButton = [self button:[self L:@"verify"] action:@selector(startVerification:) frame:NSMakeRect(282, 120, 115, 34)];
    self.logButton = [self button:[self L:@"open_log"] action:@selector(openLog:) frame:NSMakeRect(409, 120, 105, 34)];
    self.revealButton = [self button:[self L:@"show_destination"] action:@selector(revealDestination:) frame:NSMakeRect(526, 120, 145, 34)];
    for (NSButton *button in @[self.startButton, self.pauseButton, self.verifyButton, self.logButton, self.revealButton]) [content addSubview:button];

    self.noteLabel = [self label:[self L:@"note"] size:12 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor];
    self.noteLabel.frame = NSMakeRect(28, 68, 764, 34);
    self.noteLabel.maximumNumberOfLines = 2;
    [content addSubview:self.noteLabel];
    [self updateLocalizedTexts];
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
    panel.prompt = [self L:@"add_prompt"];
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
        if (conflicts.count) [self showAlert:[NSString stringWithFormat:[self L:@"error_duplicate_add"], [conflicts componentsJoinedByString:@", "]]];
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
    panel.prompt = [self L:@"select_prompt"];
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

- (NSArray<NSString *> *)readLines:(NSString *)path {
    NSString *text = [self readText:path];
    return text.length ? [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] : @[];
}

- (NSString *)localizedWorkerStatus:(NSString *)code arguments:(NSArray<NSString *> *)arguments {
    if (!code.length) return nil;
    NSString *(^arg)(NSUInteger) = ^NSString *(NSUInteger index) { return index < arguments.count ? arguments[index] : @""; };
    if ([code isEqualToString:@"lock_failed"] || [code isEqualToString:@"paused"]) return [self L:[@"worker_" stringByAppendingString:code]];
    if ([code isEqualToString:@"destination_unavailable"] || [code isEqualToString:@"source_unavailable"] || [code isEqualToString:@"duplicate_source"] || [code isEqualToString:@"recursive_target"]) {
        return [NSString stringWithFormat:[self L:[@"worker_" stringByAppendingString:code]], arg(0)];
    }
    if ([code isEqualToString:@"copying"] || [code isEqualToString:@"completed_skip"] || [code isEqualToString:@"verifying"] || [code isEqualToString:@"verify_failed"] || [code isEqualToString:@"verify_difference"] || [code isEqualToString:@"copy_interrupted"]) {
        return [NSString stringWithFormat:[self L:[@"worker_" stringByAppendingString:code]], arg(0), arg(1), arg(2)];
    }
    if ([code isEqualToString:@"all_verified"] || [code isEqualToString:@"all_copied"]) {
        return [NSString stringWithFormat:[self L:[@"worker_" stringByAppendingString:code]], arg(0)];
    }
    return nil;
}

- (pid_t)activePID {
    pid_t pid = (pid_t)[[self readText:[[self stateRoot] stringByAppendingPathComponent:@"worker.pid"]] intValue];
    return (pid > 1 && kill(pid, 0) == 0) ? pid : 0;
}

- (void)refreshStatus {
    BOOL running = [self activePID] != 0;
    NSString *statusCode = [self readText:[[self stateRoot] stringByAppendingPathComponent:@"status-code.txt"]];
    NSArray *statusArguments = [self readLines:[[self stateRoot] stringByAppendingPathComponent:@"status-arguments.txt"]];
    NSString *workerStatus = [self localizedWorkerStatus:statusCode arguments:statusArguments];
    if (self.sources.count == 0) self.statusLabel.stringValue = [self L:@"status_choose_source"];
    else if (self.destination.length == 0) self.statusLabel.stringValue = [self L:@"status_choose_destination"];
    else if (![NSFileManager.defaultManager fileExistsAtPath:self.destination]) self.statusLabel.stringValue = [self L:@"status_destination_unavailable"];
    else if (workerStatus.length) self.statusLabel.stringValue = workerStatus;
    else if (running) self.statusLabel.stringValue = [self L:@"status_launching"];
    else self.statusLabel.stringValue = [NSString stringWithFormat:[self L:@"status_ready"], (unsigned long)self.sources.count];

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
        self.progressLabel.stringValue = [self L:@"progress_scanning"];
    } else {
        self.progressBar.indeterminate = NO;
        [self.progressBar stopAnimation:nil];
        BOOL complete = [statusCode isEqualToString:@"all_copied"] || [statusCode isEqualToString:@"all_verified"];
        self.progressBar.doubleValue = complete ? 100 : 0;
        self.progressLabel.stringValue = complete ? [self L:@"progress_complete"] : [self L:@"progress_waiting"];
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
    if (self.sources.count == 0) return [self L:@"error_no_source"];
    if (self.destination.length == 0) return [self L:@"error_no_destination"];
    if (![NSFileManager.defaultManager fileExistsAtPath:self.destination]) return [self L:@"error_destination_unavailable"];
    NSMutableSet *names = [NSMutableSet set];
    for (NSString *source in self.sources) {
        if (![NSFileManager.defaultManager fileExistsAtPath:source]) return [NSString stringWithFormat:[self L:@"error_source_unavailable"], source];
        NSString *name = source.lastPathComponent.lowercaseString;
        if ([names containsObject:name]) return [NSString stringWithFormat:[self L:@"error_duplicate_source"], source.lastPathComponent];
        [names addObject:name];
        NSString *target = [self.destination stringByAppendingPathComponent:source.lastPathComponent].stringByStandardizingPath;
        NSString *standardSource = source.stringByStandardizingPath;
        if ([target isEqualToString:standardSource] || [target hasPrefix:[standardSource stringByAppendingString:@"/"]]) {
            return [NSString stringWithFormat:[self L:@"error_recursive"], source];
        }
    }
    return nil;
}

- (void)showAlert:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [self L:@"alert_title"];
    alert.informativeText = message;
    [alert runModal];
}

- (void)launchWorker:(BOOL)verifyOnly {
    NSString *error = [self configurationError];
    if (error) { [self showAlert:error]; return; }
    NSString *script = [NSBundle.mainBundle pathForResource:@"transfer" ofType:@"zsh"];
    if (!script) { [self showAlert:[self L:@"error_missing_component"]] ; return; }
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
        self.statusLabel.stringValue = [self L:@"status_launching"];
        [self performSelector:@selector(refreshStatus) withObject:nil afterDelay:0.8];
    } @catch (NSException *exception) {
        [self showAlert:[NSString stringWithFormat:[self L:@"error_start"], exception.reason ?: [self L:@"unknown_error"]]];
    }
}

- (void)startTransfer:(id)sender { [self launchWorker:NO]; }
- (void)resumeAfterLaunch { [self launchWorker:NO]; }
- (void)startVerification:(id)sender { [self launchWorker:YES]; }

- (void)pauseTransfer:(id)sender {
    pid_t pid = [self activePID];
    if (!pid) { [self refreshStatus]; return; }
    if (kill(pid, SIGTERM) == 0) self.statusLabel.stringValue = [self L:@"status_pausing"];
    else [self showAlert:[self L:@"error_pause"]];
}

- (void)openLog:(id)sender {
    if (self.destination.length == 0) { [self showAlert:[self L:@"error_no_destination"]] ; return; }
    NSString *root = [self stateRoot];
    NSString *path = [root stringByAppendingPathComponent:@"transfer.log"];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) [NSFileManager.defaultManager createFileAtPath:path contents:NSData.data attributes:nil];
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:path]];
}

- (void)revealDestination:(id)sender {
    if (self.destination.length == 0) { [self showAlert:[self L:@"error_no_destination"]] ; return; }
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
