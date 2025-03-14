<script context="module">
	let cssClassesLoaded = writable(false)
	let tailwindClassesLoaded = writable(false)
</script>

<script lang="ts">
	import { BROWSER } from 'esm-env'

	import { createHash, editorConfig, langToExt, updateOptions } from '$lib/editorUtils'
	import {
		editor as meditor,
		KeyCode,
		KeyMod,
		Uri as mUri,
		languages,
		type IRange
	} from 'monaco-editor'
	import 'monaco-editor/esm/vs/basic-languages/sql/sql.contribution'
	import 'monaco-editor/esm/vs/basic-languages/yaml/yaml.contribution'
	import 'monaco-editor/esm/vs/basic-languages/javascript/javascript.contribution'
	import 'monaco-editor/esm/vs/language/json/monaco.contribution'
	import 'monaco-editor/esm/vs/basic-languages/css/css.contribution'
	import 'monaco-editor/esm/vs/language/css/monaco.contribution'

	import { allClasses } from './apps/editor/componentsPanel/cssUtils'

	import { createEventDispatcher, onDestroy, onMount } from 'svelte'

	import libStdContent from '$lib/es6.d.ts.txt?raw'
	import domContent from '$lib/dom.d.ts.txt?raw'
	import { buildWorkerDefinition } from './build_workers'
	import { initializeVscode } from './vscode'
	import EditorTheme from './EditorTheme.svelte'
	import { tailwindClasses } from './apps/editor/componentsPanel/tailwindUtils'
	import { writable } from 'svelte/store'
	// import { createConfiguredEditor } from 'vscode/monaco'
	// import type { IStandaloneCodeEditor } from 'vscode/vscode/vs/editor/standalone/browser/standaloneCodeEditor'

	let divEl: HTMLDivElement | null = null
	let editor: meditor.IStandaloneCodeEditor
	let model: meditor.ITextModel

	export let lang: string
	export let code: string = ''
	export let hash: string = createHash()
	export let cmdEnterAction: (() => void) | undefined = undefined
	export let formatAction: (() => void) | undefined = undefined
	export let automaticLayout = true
	export let extraLib: string = ''

	export let shouldBindKey: boolean = true
	export let autoHeight = false
	export let fixedOverflowWidgets = true
	export let small = false
	export let domLib = false
	export let autofocus = false

	const dispatch = createEventDispatcher()

	const uri = `file:///${hash}.${langToExt(lang)}`

	buildWorkerDefinition('../../../workers', import.meta.url, false)

	export function getCode(): string {
		return editor?.getValue() ?? ''
	}

	export function insertAtCursor(code: string): void {
		if (editor) {
			editor.trigger('keyboard', 'type', { text: code })
		}
	}

	export function setCode(ncode: string): void {
		code = ncode
		if (editor) {
			editor.setValue(ncode)
		}
	}

	export function format() {
		if (editor) {
			code = getCode()
			editor.getAction('editor.action.formatDocument')?.run()
			if (formatAction) {
				formatAction()
				code = getCode()
			}
		}
	}

	export function focus() {
		editor?.focus()
	}

	export function getSelectedLines(): string | undefined {
		if (editor) {
			const selection = editor.getSelection()
			if (selection) {
				const range: IRange = {
					startLineNumber: selection.startLineNumber,
					startColumn: 1,
					endLineNumber: selection.endLineNumber + 1,
					endColumn: 1
				}
				return editor.getModel()?.getValueInRange(range)
			}
		}
	}

	export function onDidChangeCursorSelection(f: (e: meditor.ICursorSelectionChangedEvent) => void) {
		if (editor) {
			return editor.onDidChangeCursorSelection(f)
		}
	}

	export function show(): void {
		divEl?.classList.remove('hidden')
	}

	export function hide(): void {
		divEl?.classList.add('hidden')
	}

	let suggestion = ''
	export function setSuggestion(value: string): void {
		suggestion = value
	}

	let width = 0
	let initialized = false

	let disableTabCond: meditor.IContextKey<boolean> | undefined
	$: disableTabCond?.set(!code && !!suggestion)

	async function loadMonaco() {
		await initializeVscode()
		initialized = true
		languages.typescript.javascriptDefaults.setCompilerOptions({
			target: languages.typescript.ScriptTarget.Latest,
			allowNonTsExtensions: true,
			noSemanticValidation: false,
			noLib: true,
			moduleResolution: languages.typescript.ModuleResolutionKind.NodeJs
		})
		languages.typescript.javascriptDefaults.setDiagnosticsOptions({
			noSemanticValidation: false,
			noSyntaxValidation: false,
			noSuggestionDiagnostics: false,
			diagnosticCodesToIgnore: [1108]
		})

		languages.json.jsonDefaults.setDiagnosticsOptions({
			validate: true,
			allowComments: false,
			schemas: [],
			enableSchemaRequest: true
		})

		try {
			model = meditor.createModel(code, lang, mUri.parse(uri))
		} catch (err) {
			console.log('model already existed', err)
			const nmodel = meditor.getModel(mUri.parse(uri))
			if (!nmodel) {
				throw err
			}
			model = nmodel
		}
		model.updateOptions(updateOptions)
		// let widgets: HTMLElement | undefined =
		// 	document.getElementById('monaco-widgets-root') ?? undefined

		if (!divEl) {
			return
		}
		editor = meditor.create(divEl as HTMLDivElement, {
			...editorConfig(code, lang, automaticLayout, fixedOverflowWidgets),
			model,
			// overflowWidgetsDomNode: widgets,
			fontSize: small ? 12 : 14
		})

		let timeoutModel: NodeJS.Timeout | undefined = undefined
		editor.onDidChangeModelContent((event) => {
			suggestion = ''
			timeoutModel && clearTimeout(timeoutModel)
			timeoutModel = setTimeout(() => {
				code = getCode()
				dispatch('change', { code })
			}, 200)
		})

		editor.onDidFocusEditorText(() => {
			dispatch('focus')

			editor.addCommand(KeyMod.CtrlCmd | KeyCode.KeyS, function () {
				code = getCode()
				shouldBindKey && format && format()
			})

			disableTabCond = editor.createContextKey('disableTabCond', !code)
			editor.addCommand(KeyCode.Tab, function () {}, 'disableTabCond')
		})

		if (autoHeight) {
			const updateHeight = () => {
				const contentHeight = Math.min(1000, editor.getContentHeight())
				if (divEl) {
					divEl.style.height = `${contentHeight}px`
				}
				try {
					editor.layout({ width, height: contentHeight })
				} finally {
				}
			}
			editor.onDidContentSizeChange(updateHeight)
			updateHeight()
		}

		editor.onDidFocusEditorText(() => {
			editor.addCommand(KeyMod.CtrlCmd | KeyCode.KeyS, function () {
				code = getCode()
				shouldBindKey && format && format()
			})

			editor.addCommand(KeyMod.CtrlCmd | KeyCode.Enter, function () {
				code = getCode()
				shouldBindKey && cmdEnterAction && cmdEnterAction()
			})
			dispatch('focus')
		})

		editor.onDidBlurEditorText(() => {
			dispatch('blur')
			code = getCode()
		})

		if (lang === 'css' && !$cssClassesLoaded) {
			$cssClassesLoaded = true
			addCSSClassCompletions()
		}

		if (lang === 'tailwindcss' && !$tailwindClassesLoaded) {
			languages.register({ id: 'tailwindcss' })
			$tailwindClassesLoaded = true
			addTailwindClassCompletions()
		}
	}

	function addCSSClassCompletions() {
		languages.registerCompletionItemProvider('css', {
			provideCompletionItems: function (model, position, context, token) {
				const word = model.getWordUntilPosition(position)
				const range = {
					startLineNumber: position.lineNumber,
					startColumn: word.startColumn,
					endLineNumber: position.lineNumber,
					endColumn: word.endColumn
				}

				if (word && word.word) {
					const currentWord = word.word

					const suggestions = allClasses
						.filter((className) => className.includes(currentWord))
						.map((className) => ({
							label: className,
							kind: languages.CompletionItemKind.Class,
							insertText: className,
							documentation: 'Custom CSS class',
							range: range
						}))

					return { suggestions }
				}

				return { suggestions: [] }
			}
		})
	}

	function addTailwindClassCompletions() {
		languages.registerCompletionItemProvider('tailwindcss', {
			provideCompletionItems: function (model, position, context, token) {
				const word = model.getWordUntilPosition(position)
				const range = {
					startLineNumber: position.lineNumber,
					startColumn: word.startColumn,
					endLineNumber: position.lineNumber,
					endColumn: word.endColumn
				}

				if (word && word.word) {
					const currentWord = word.word

					const suggestions = tailwindClasses
						.filter((className) => className.includes(currentWord))
						.map((className) => ({
							label: className,
							kind: languages.CompletionItemKind.Class,
							insertText: className,
							documentation: 'Custom CSS class',
							range: range
						}))

					return { suggestions }
				}

				return { suggestions: [] }
			}
		})
	}

	function loadExtraLib() {
		if (lang == 'javascript') {
			const stdLib = { content: libStdContent, filePath: 'es6.d.ts' }
			const libs = [stdLib]
			if (domLib) {
				const domDTS = { content: domContent, filePath: 'dom.d.ts' }
				libs.push(domDTS)
			}
			if (extraLib != '') {
				libs.push({
					content: extraLib,
					filePath: 'windmill.d.ts'
				})
			}
			console.log(libs)
			languages.typescript.javascriptDefaults.setExtraLibs(libs)
		}
	}

	let mounted = false
	onMount(async () => {
		if (BROWSER) {
			mounted = true
			await loadMonaco()
			if (autofocus) {
				setTimeout(() => {
					focus()
				}, 0)
			}
		}
	})

	$: mounted && extraLib && initialized && loadExtraLib()

	onDestroy(() => {
		try {
			model && model.dispose()
			editor && editor.dispose()
		} catch (err) {}
	})
</script>

<EditorTheme />

{#if editor && suggestion && code.length === 0}
	<div
		class="absolute top-[0.05rem] left-[2.05rem] z-10 text-sm text-[#0007] italic font-mono dark:text-[#ffffff56] text-ellipsis overflow-hidden whitespace-nowrap"
		style={`max-width: calc(${width}px - 2.05rem)`}
	>
		{suggestion}
	</div>
{/if}

<div bind:this={divEl} class="{$$props.class ?? ''} editor" bind:clientWidth={width} />

<style lang="postcss">
	.editor {
		@apply rounded-lg p-0;
	}

	.small-editor {
		/* stylelint-disable-next-line unit-allowed-list */
		height: 26vh;
	}

	.few-lines-editor {
		/* stylelint-disable-next-line unit-allowed-list */
		height: 100px;
	}
</style>
