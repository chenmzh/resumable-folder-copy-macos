#import <Cocoa/Cocoa.h>
#import <limits.h>
#import <signal.h>

static NSString * const SourcesDefaultsKey = @"TransferSources";
static NSString * const DestinationDefaultsKey = @"TransferDestination";
static NSString * const LanguageDefaultsKey = @"InterfaceLanguage";
static NSString * const RememberTaskDefaultsKey = @"RememberLastTask";

@interface CapacityBarView : NSView
@property(nonatomic) double value;
@property(nonatomic) NSColor *fillColor;
@end

@implementation CapacityBarView
- (BOOL)isFlipped { return YES; }
- (void)setValue:(double)value { _value = MIN(100.0, MAX(0.0, value)); [self setNeedsDisplay:YES]; }
- (void)setFillColor:(NSColor *)fillColor { _fillColor = fillColor; [self setNeedsDisplay:YES]; }
- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:5 yRadius:5];
    [NSColor.separatorColor setFill];
    [background fill];
    if (self.value <= 0) return;
    NSRect fillRect = bounds;
    fillRect.size.width = MAX(5.0, bounds.size.width * self.value / 100.0);
    NSBezierPath *fill = [NSBezierPath bezierPathWithRoundedRect:fillRect xRadius:5 yRadius:5];
    [(self.fillColor ?: NSColor.systemGrayColor) setFill];
    [fill fill];
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property NSWindow *window;
@property NSMutableArray<NSString *> *sources;
@property NSString *destination;
@property NSString *languageCode;
@property BOOL rememberTasks;
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
@property NSBox *spaceBox;
@property NSTextField *spaceSummaryLabel;
@property NSTextField *spaceDetailLabel;
@property CapacityBarView *spaceBar;
@property NSString *spaceResultCode;
@property NSPopUpButton *languagePopup;
@property NSButton *chooseSourcesButton;
@property NSButton *removeButton;
@property NSButton *clearButton;
@property NSButton *rememberTaskToggle;
@property NSButton *chooseDestinationButton;
@property NSButton *checkSpaceButton;
@property NSButton *startButton;
@property NSButton *pauseButton;
@property NSButton *verifyButton;
@property NSButton *logButton;
@property NSButton *revealButton;
@property NSButton *skippedButton;
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
    self.rememberTasks = [defaults boolForKey:RememberTaskDefaultsKey];
    NSArray *savedSources = self.rememberTasks ? [defaults stringArrayForKey:SourcesDefaultsKey] : nil;
    NSString *savedDestination = self.rememberTasks ? [defaults stringForKey:DestinationDefaultsKey] : nil;
    self.sources = savedSources ? [savedSources mutableCopy] : [NSMutableArray array];
    self.destination = savedDestination ?: @"";
    self.languageCode = [defaults stringForKey:LanguageDefaultsKey] ?: @"en";
    if (!self.rememberTasks) {
        [defaults removeObjectForKey:SourcesDefaultsKey];
        [defaults removeObjectForKey:DestinationDefaultsKey];
    }
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
    self.rememberTaskToggle.title = [self L:@"remember_last_task"];
    self.chooseDestinationButton.title = [self L:@"choose_destination"];
    self.spaceBox.title = [self L:@"space_title"];
    self.checkSpaceButton.title = [self L:@"check_space"];
    self.startButton.title = [self L:@"start_resume"];
    self.pauseButton.title = [self L:@"pause"];
    self.verifyButton.title = [self L:@"verify"];
    self.logButton.title = [self L:@"open_log"];
    self.revealButton.title = [self L:@"show_destination"];
    self.skippedButton.title = [self L:@"show_skipped_files"];
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
    [defaults setBool:self.rememberTasks forKey:RememberTaskDefaultsKey];
    if (self.rememberTasks) {
        [defaults setObject:self.sources forKey:SourcesDefaultsKey];
        [defaults setObject:self.destination ?: @"" forKey:DestinationDefaultsKey];
    } else {
        [defaults removeObjectForKey:SourcesDefaultsKey];
        [defaults removeObjectForKey:DestinationDefaultsKey];
    }
}

- (void)toggleRememberTask:(id)sender {
    self.rememberTasks = self.rememberTaskToggle.state == NSControlStateValueOn;
    [self saveConfiguration];
}

- (void)buildWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 820, 760)
                                               styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                 backing:NSBackingStoreBuffered defer:NO];
    self.window.title = [self L:@"app_title"];
    [self.window center];
    NSView *content = self.window.contentView;

    self.titleLabel = [self label:[self L:@"app_title"] size:25 weight:NSFontWeightSemibold color:NSColor.labelColor];
    self.titleLabel.frame = NSMakeRect(28, 710, 500, 34);
    [content addSubview:self.titleLabel];
    self.languageLabel = [self label:[self L:@"language_label"] size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    self.languageLabel.alignment = NSTextAlignmentRight;
    self.languageLabel.frame = NSMakeRect(540, 717, 90, 22);
    [content addSubview:self.languageLabel];
    self.languagePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(640, 710, 152, 30) pullsDown:NO];
    self.languagePopup.target = self;
    self.languagePopup.action = @selector(changeLanguage:);
    for (NSDictionary *option in [self languageOptions]) {
        [self.languagePopup addItemWithTitle:option[@"name"]];
        self.languagePopup.lastItem.representedObject = option[@"code"];
        if ([option[@"code"] isEqualToString:self.languageCode]) [self.languagePopup selectItem:self.languagePopup.lastItem];
    }
    [content addSubview:self.languagePopup];
    self.subtitleLabel = [self label:[self L:@"subtitle"] size:13 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    self.subtitleLabel.frame = NSMakeRect(28, 684, 764, 22);
    [content addSubview:self.subtitleLabel];

    self.sourceTitleLabel = [self label:[self L:@"source_title"] size:14 weight:NSFontWeightSemibold color:NSColor.labelColor];
    self.sourceTitleLabel.frame = NSMakeRect(28, 648, 760, 22);
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
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(28, 505, 764, 135)];
    scroll.documentView = self.sourceTable;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    [content addSubview:scroll];

    self.chooseSourcesButton = [self button:[self L:@"choose_sources"] action:@selector(chooseSources:) frame:NSMakeRect(28, 464, 150, 32)];
    self.removeButton = [self button:[self L:@"remove_selected"] action:@selector(removeSelectedSources:) frame:NSMakeRect(190, 464, 120, 32)];
    self.clearButton = [self button:[self L:@"clear_list"] action:@selector(clearSources:) frame:NSMakeRect(322, 464, 110, 32)];
    [content addSubview:self.chooseSourcesButton];
    [content addSubview:self.removeButton];
    [content addSubview:self.clearButton];
    self.rememberTaskToggle = [NSButton checkboxWithTitle:[self L:@"remember_last_task"] target:self action:@selector(toggleRememberTask:)];
    self.rememberTaskToggle.frame = NSMakeRect(452, 467, 340, 26);
    self.rememberTaskToggle.state = self.rememberTasks ? NSControlStateValueOn : NSControlStateValueOff;
    [content addSubview:self.rememberTaskToggle];

    self.destinationTitleLabel = [self label:[self L:@"destination_title"] size:14 weight:NSFontWeightSemibold color:NSColor.labelColor];
    self.destinationTitleLabel.frame = NSMakeRect(28, 426, 300, 22);
    [content addSubview:self.destinationTitleLabel];
    self.destinationField = [[NSTextField alloc] initWithFrame:NSMakeRect(28, 388, 610, 30)];
    self.destinationField.editable = NO;
    self.destinationField.selectable = YES;
    self.destinationField.stringValue = self.destination ?: @"";
    [content addSubview:self.destinationField];
    self.chooseDestinationButton = [self button:[self L:@"choose_destination"] action:@selector(chooseDestination:) frame:NSMakeRect(650, 387, 142, 32)];
    [content addSubview:self.chooseDestinationButton];

    self.spaceBox = [[NSBox alloc] initWithFrame:NSMakeRect(28, 275, 764, 100)];
    self.spaceBox.title = [self L:@"space_title"];
    [content addSubview:self.spaceBox];
    self.spaceSummaryLabel = [self label:[self L:@"space_not_checked"] size:14 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
    self.spaceSummaryLabel.frame = NSMakeRect(16, 53, 570, 22);
    [self.spaceBox.contentView addSubview:self.spaceSummaryLabel];
    self.spaceBar = [[CapacityBarView alloc] initWithFrame:NSMakeRect(16, 34, 570, 12)];
    self.spaceBar.value = 0;
    [self.spaceBox.contentView addSubview:self.spaceBar];
    self.spaceDetailLabel = [self label:@"" size:11 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    self.spaceDetailLabel.frame = NSMakeRect(16, 8, 570, 18);
    [self.spaceBox.contentView addSubview:self.spaceDetailLabel];
    self.checkSpaceButton = [self button:[self L:@"check_space"] action:@selector(checkSpace:) frame:NSMakeRect(602, 31, 136, 32)];
    [self.spaceBox.contentView addSubview:self.checkSpaceButton];

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

    self.startButton = [self button:[self L:@"start_resume"] action:@selector(startTransfer:) frame:NSMakeRect(28, 120, 130, 34)];
    self.pauseButton = [self button:[self L:@"pause"] action:@selector(pauseTransfer:) frame:NSMakeRect(166, 120, 88, 34)];
    self.verifyButton = [self button:[self L:@"verify"] action:@selector(startVerification:) frame:NSMakeRect(262, 120, 110, 34)];
    self.logButton = [self button:[self L:@"open_log"] action:@selector(openLog:) frame:NSMakeRect(380, 120, 96, 34)];
    self.revealButton = [self button:[self L:@"show_destination"] action:@selector(revealDestination:) frame:NSMakeRect(484, 120, 130, 34)];
    self.skippedButton = [self button:[self L:@"show_skipped_files"] action:@selector(openSkippedFiles:) frame:NSMakeRect(622, 120, 170, 34)];
    for (NSButton *button in @[self.startButton, self.pauseButton, self.verifyButton, self.logButton, self.revealButton, self.skippedButton]) [content addSubview:button];

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

- (NSString *)canonicalPath:(NSString *)path {
    return path.stringByStandardizingPath.stringByResolvingSymlinksInPath;
}

- (BOOL)preflightConfigurationMatches:(NSArray<NSString *> *)configuration {
    if (!self.destination.length || configuration.count != self.sources.count + 1) return NO;
    if (![[self canonicalPath:configuration[0]] isEqualToString:[self canonicalPath:self.destination]]) return NO;
    for (NSUInteger index = 0; index < self.sources.count; index++) {
        if (![[self canonicalPath:configuration[index + 1]] isEqualToString:[self canonicalPath:self.sources[index]]]) return NO;
    }
    return YES;
}

- (NSString *)formattedBytes:(unsigned long long)bytes {
    return [NSByteCountFormatter stringFromByteCount:(long long)MIN(bytes, (unsigned long long)LLONG_MAX)
                                          countStyle:NSByteCountFormatterCountStyleFile];
}

- (void)refreshSpacePanel {
    NSArray<NSString *> *configuration = [self readLines:[[self stateRoot] stringByAppendingPathComponent:@"preflight-config.txt"]];
    NSString *code = [self readText:[[self stateRoot] stringByAppendingPathComponent:@"preflight-code.txt"]];
    if (![self preflightConfigurationMatches:configuration]) code = nil;
    self.spaceResultCode = code;

    self.spaceBar.value = 0;
    self.spaceBar.fillColor = NSColor.systemGrayColor;
    self.spaceDetailLabel.stringValue = @"";

    if (!code.length) {
        self.spaceSummaryLabel.stringValue = [self L:@"space_not_checked"];
        self.spaceSummaryLabel.textColor = NSColor.secondaryLabelColor;
        return;
    }
    if ([code isEqualToString:@"checking"]) {
        self.spaceSummaryLabel.stringValue = [self L:@"space_checking"];
        self.spaceSummaryLabel.textColor = NSColor.systemBlueColor;
        self.spaceBar.value = 18;
        self.spaceBar.fillColor = NSColor.systemBlueColor;
        return;
    }

    NSArray<NSString *> *values = [self readLines:[[self stateRoot] stringByAppendingPathComponent:@"preflight-values.txt"]];
    if (values.count < 4) {
        self.spaceSummaryLabel.stringValue = [self L:@"space_error"];
        self.spaceSummaryLabel.textColor = NSColor.systemRedColor;
        return;
    }
    unsigned long long required = values[0].longLongValue < 0 ? 0 : (unsigned long long)values[0].longLongValue;
    unsigned long long available = values[1].longLongValue < 0 ? 0 : (unsigned long long)values[1].longLongValue;
    unsigned long long reserve = values[2].longLongValue < 0 ? 0 : (unsigned long long)values[2].longLongValue;
    double percent = available > 0 ? 100.0 * ((double)required + (double)reserve) / (double)available : 100.0;
    self.spaceBar.value = MIN(100.0, MAX(0.0, percent));
    self.spaceDetailLabel.stringValue = [NSString stringWithFormat:[self L:@"space_detail"],
                                              [self formattedBytes:required], [self formattedBytes:available], [self formattedBytes:reserve]];

    if ([code isEqualToString:@"ok"]) {
        self.spaceSummaryLabel.stringValue = [self L:@"space_ok"];
        self.spaceSummaryLabel.textColor = NSColor.systemGreenColor;
        self.spaceBar.fillColor = NSColor.systemGreenColor;
    } else if ([code isEqualToString:@"warning"]) {
        self.spaceSummaryLabel.stringValue = [self L:@"space_warning"];
        self.spaceSummaryLabel.textColor = NSColor.systemOrangeColor;
        self.spaceBar.fillColor = NSColor.systemOrangeColor;
    } else if ([code isEqualToString:@"insufficient"]) {
        self.spaceSummaryLabel.stringValue = [self L:@"space_insufficient"];
        self.spaceSummaryLabel.textColor = NSColor.systemRedColor;
        self.spaceBar.fillColor = NSColor.systemRedColor;
    } else {
        self.spaceSummaryLabel.stringValue = [self L:@"space_error"];
        self.spaceSummaryLabel.textColor = NSColor.systemRedColor;
        self.spaceBar.fillColor = NSColor.systemRedColor;
    }
}

- (NSString *)localizedWorkerStatus:(NSString *)code arguments:(NSArray<NSString *> *)arguments {
    if (!code.length) return nil;
    NSString *(^arg)(NSUInteger) = ^NSString *(NSUInteger index) { return index < arguments.count ? arguments[index] : @""; };
    if ([code isEqualToString:@"lock_failed"] || [code isEqualToString:@"paused"]) return [self L:[@"worker_" stringByAppendingString:code]];
    if ([code isEqualToString:@"destination_unavailable"] || [code isEqualToString:@"source_unavailable"] || [code isEqualToString:@"duplicate_source"] || [code isEqualToString:@"recursive_target"]) {
        return [NSString stringWithFormat:[self L:[@"worker_" stringByAppendingString:code]], arg(0)];
    }
    if ([code isEqualToString:@"copying"] || [code isEqualToString:@"completed_skip"] || [code isEqualToString:@"verifying"] || [code isEqualToString:@"verify_failed"] || [code isEqualToString:@"verify_difference"] || [code isEqualToString:@"copy_interrupted"] || [code isEqualToString:@"preflight_directory_skipped"] || [code isEqualToString:@"directory_skipped"]) {
        return [NSString stringWithFormat:[self L:[@"worker_" stringByAppendingString:code]], arg(0), arg(1), arg(2)];
    }
    if ([code isEqualToString:@"retrying_unreadable"] || [code isEqualToString:@"copied_with_skips"]) {
        return [NSString stringWithFormat:[self L:[@"worker_" stringByAppendingString:code]], arg(0), arg(1), arg(2), arg(3)];
    }
    if ([code isEqualToString:@"preflight_scanning"]) {
        return [NSString stringWithFormat:[self L:@"worker_preflight_scanning"], arg(0), arg(1), arg(2)];
    }
    if ([code isEqualToString:@"preflight_ok"] || [code isEqualToString:@"preflight_warning"] || [code isEqualToString:@"preflight_insufficient"]) {
        return [self L:[@"worker_" stringByAppendingString:code]];
    }
    if ([code isEqualToString:@"preflight_error"]) {
        return [NSString stringWithFormat:[self L:@"worker_preflight_error"], arg(0)];
    }
    if ([code isEqualToString:@"all_verified"] || [code isEqualToString:@"all_copied"]) {
        return [NSString stringWithFormat:[self L:[@"worker_" stringByAppendingString:code]], arg(0)];
    }
    if ([code isEqualToString:@"all_copied_with_skips"]) {
        return [NSString stringWithFormat:[self L:@"worker_all_copied_with_skips"], arg(0), arg(1)];
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
    [self refreshSpacePanel];
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
        BOOL complete = [statusCode isEqualToString:@"all_copied"] || [statusCode isEqualToString:@"all_copied_with_skips"] || [statusCode isEqualToString:@"all_verified"];
        self.progressBar.doubleValue = complete ? 100 : 0;
        self.progressLabel.stringValue = complete ? [self L:@"progress_complete"] : [self L:@"progress_waiting"];
    }

    BOOL configurable = !running;
    self.chooseSourcesButton.enabled = configurable;
    self.removeButton.enabled = configurable && self.sourceTable.selectedRowIndexes.count > 0;
    self.clearButton.enabled = configurable && self.sources.count > 0;
    self.chooseDestinationButton.enabled = configurable;
    BOOL hasConfiguration = self.sources.count > 0 && self.destination.length > 0;
    self.checkSpaceButton.enabled = configurable && hasConfiguration;
    self.startButton.enabled = configurable && hasConfiguration && ![self.spaceResultCode isEqualToString:@"insufficient"];
    self.verifyButton.enabled = configurable && hasConfiguration;
    self.pauseButton.enabled = running;
    NSArray<NSString *> *skippedConfiguration = [self readLines:[[self stateRoot] stringByAppendingPathComponent:@"preflight-config.txt"]];
    NSArray<NSString *> *skippedFiles = [self preflightConfigurationMatches:skippedConfiguration]
        ? [self readLines:[[self stateRoot] stringByAppendingPathComponent:@"skipped-unreadable-files.txt"]] : @[];
    self.skippedButton.title = skippedFiles.count
        ? [NSString stringWithFormat:[self L:@"show_skipped_count"], (unsigned long)skippedFiles.count]
        : [self L:@"show_skipped_files"];
    self.skippedButton.enabled = skippedFiles.count > 0;
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

- (void)launchWorkerWithOption:(NSString *)option {
    NSString *error = [self configurationError];
    if (error) { [self showAlert:error]; return; }
    NSString *script = [NSBundle.mainBundle pathForResource:@"transfer" ofType:@"zsh"];
    if (!script) { [self showAlert:[self L:@"error_missing_component"]] ; return; }
    NSMutableArray *arguments = [NSMutableArray arrayWithObjects:script, @"--destination", self.destination, nil];
    if (option.length) [arguments addObject:option];
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

- (void)startTransfer:(id)sender { [self launchWorkerWithOption:@"--preflight-first"]; }
- (void)resumeAfterLaunch { [self launchWorkerWithOption:@"--preflight-first"]; }
- (void)startVerification:(id)sender { [self launchWorkerWithOption:@"--verify-only"]; }
- (void)checkSpace:(id)sender { [self launchWorkerWithOption:@"--preflight-only"]; }

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

- (void)openSkippedFiles:(id)sender {
    NSString *path = [[self stateRoot] stringByAppendingPathComponent:@"skipped-unreadable-files.txt"];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) return;
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
