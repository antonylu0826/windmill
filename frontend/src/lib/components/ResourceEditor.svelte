<script lang="ts">
	import type { Schema } from '$lib/common'
	import { ResourceService, type Resource, type ResourceType } from '$lib/gen'
	import { canWrite, emptyString, isOwner, urlize } from '$lib/utils'
	import { createEventDispatcher } from 'svelte'
	import { Alert, Button, Drawer, Skeleton } from './common'
	import Path from './Path.svelte'
	import Required from './Required.svelte'

	import { userStore, workspaceStore } from '$lib/stores'
	import DrawerContent from './common/drawer/DrawerContent.svelte'
	import SchemaForm from './SchemaForm.svelte'
	import SimpleEditor from './SimpleEditor.svelte'
	import Toggle from './Toggle.svelte'
	import { sendUserToast } from '$lib/toast'
	import TestConnection from './TestConnection.svelte'
	import { Pen, Save } from 'lucide-svelte'
	import Markdown from 'svelte-exmarkdown'
	import autosize from '$lib/autosize'
	import GfmMarkdown from './GfmMarkdown.svelte'

	let path = ''
	let initialPath = ''

	let resourceToEdit: Resource | undefined

	let description: string = ''
	let DESCRIPTION_PLACEHOLDER = `Describe what this resource is for`
	let selectedResourceType: string | undefined
	let resourceSchema: Schema | undefined
	let args: Record<string, any> = {}
	let can_write = true
	let loadingSchema = false
	let linkedVars: string[] = []
	let drawer: Drawer
	let resourceTypeInfo: ResourceType | undefined = undefined
	let renderDescription = true

	let rawCode: string | undefined = undefined

	const dispatch = createEventDispatcher()

	export async function initEdit(p: string): Promise<void> {
		initialPath = p
		path = p
		resourceToEdit = undefined
		resourceSchema = undefined
		viewJsonSchema = false
		loadingSchema = true
		drawer.openDrawer?.()
		resourceToEdit = await ResourceService.getResource({ workspace: $workspaceStore!, path: p })
		description = resourceToEdit!.description ?? ''
		selectedResourceType = resourceToEdit!.resource_type
		loadResourceType()
		args = resourceToEdit!.value
		can_write =
			resourceToEdit.workspace_id == $workspaceStore &&
			canWrite(p, resourceToEdit.extra_perms ?? {}, $userStore)
		linkedVars = Object.entries(args)
			.filter(([_, v]) => typeof v == 'string' && v == `$var:${initialPath}`)
			.map(([k, _]) => k)
		renderDescription = false
	}

	async function editResource(): Promise<void> {
		if (resourceToEdit) {
			await ResourceService.updateResource({
				workspace: $workspaceStore!,
				path: resourceToEdit.path,
				requestBody: { path, value: args, description }
			})
			sendUserToast(`Updated resource at ${path}`)
			dispatch('refresh', path)
			drawer.closeDrawer?.()
		} else {
			throw Error('Cannot edit undefined resourceToEdit')
		}
	}

	async function loadResourceType(): Promise<void> {
		if (selectedResourceType) {
			try {
				const resourceType = await ResourceService.getResourceType({
					workspace: $workspaceStore!,
					path: selectedResourceType
				})

				resourceTypeInfo = resourceType
				if (resourceType.schema) {
					resourceSchema = resourceType.schema as Schema
				}
			} catch (err) {
				resourceSchema = undefined
				loadingSchema = false
				rawCode = JSON.stringify(args, null, 2)
			}
		} else {
			sendUserToast(`ResourceType cannot be undefined.`, true)
		}
		loadingSchema = false
	}

	let isValid = true
	let jsonError = ''

	$: rawCode && parseJson()

	function parseJson() {
		try {
			args = JSON.parse(rawCode ?? '')
			jsonError = ''
		} catch (e) {
			jsonError = e.message
		}
	}

	$: linkedVars.length > 0 && path && updateArgsFromLinkedVars()

	function updateArgsFromLinkedVars() {
		linkedVars.forEach((k) => {
			args[k] = `$var:${path}`
		})
	}
	let viewJsonSchema = false

	function switchTab(asJson: boolean) {
		viewJsonSchema = asJson
		if (asJson) {
			rawCode = JSON.stringify(args, null, 2)
		} else {
			parseJson()
		}
	}
</script>

<Drawer bind:this={drawer} size="800px">
	<DrawerContent
		title={resourceToEdit ? 'Edit ' + resourceToEdit.path : 'Add a resource'}
		on:close={drawer.closeDrawer}
	>
		<div>
			<div class="flex flex-col gap-3 py-3">
				<div>
					{#if !can_write}
						<div class="m-2">
							<Alert type="warning" title="Only read access">
								You only have read access to this resource and cannot edit it
							</Alert>
						</div>
					{/if}
					<Path
						disabled={initialPath != '' && !isOwner(initialPath, $userStore, $workspaceStore)}
						bind:path
						{initialPath}
						namePlaceholder="resource"
						kind="resource"
					/>
				</div>
				{#if !emptyString(resourceTypeInfo?.description)}
					<h4 class="mt-4 mb-2">{resourceTypeInfo?.name} description</h4>
					<div class="text-sm">
						<Markdown md={urlize(resourceTypeInfo?.description ?? '', 'md')} />
					</div>
				{/if}
				<h4 class="mt-4 inline-flex items-center gap-4"
					>Resource description <Required required={false} />
					{#if can_write}
						<div class="flex gap-1 items-center">
							<Toggle size="xs" bind:checked={renderDescription} />
							<Pen size={14} />
						</div>
					{/if}</h4
				>

				{#if can_write && renderDescription}
					<div>
						<div class="flex flex-row-reverse text-2xs text-tertiary -mt-1">GH Markdown</div>
						<textarea
							disabled={!can_write}
							use:autosize
							bind:value={description}
							placeholder={DESCRIPTION_PLACEHOLDER}
						/>
					</div>
				{:else if description == undefined || description == ''}
					<div class="text-sm text-tertiary">No description provided</div>
				{:else}
					<div class="mt-2" />

					<GfmMarkdown md={description} />
				{/if}
				<div class="flex w-full justify-between max-w-lg items-center mt-4">
					<Toggle
						on:change={(e) => switchTab(e.detail)}
						options={{
							right: 'As JSON'
						}}
					/>
					<TestConnection resourceType={resourceToEdit?.resource_type} {args} />
				</div>
				<div class="text-sm">
					{#if loadingSchema}
						<Skeleton layout={[[4]]} />
					{:else if !viewJsonSchema && resourceSchema && resourceSchema?.properties}
						<SchemaForm
							noDelete
							disabled={!can_write}
							compact
							schema={resourceSchema}
							bind:args
							bind:isValid
						/>
					{:else if !can_write}
						<input type="text" disabled value={rawCode} />
					{:else}
						{#if !viewJsonSchema}
							<p class="italic text-secondary text-xs mb-4">
								No corresponding resource type found in your workspace for {selectedResourceType}.
								Define the value in JSON directly
							</p>
						{/if}

						{#if !emptyString(jsonError)}<span
								class="text-red-400 text-xs mb-1 flex flex-row-reverse">{jsonError}</span
							>{:else}<div class="py-2" />{/if}
						<div class="h-full w-full border p-1 rounded">
							<SimpleEditor
								autoHeight
								class="editor"
								lang="json"
								bind:code={rawCode}
								fixedOverflowWidgets={false}
							/>
						</div>
					{/if}
				</div>
			</div>
		</div>
		<svelte:fragment slot="actions">
			<Button
				startIcon={{ icon: Save }}
				on:click={editResource}
				disabled={!can_write || !isValid || jsonError != ''}
			>
				Save
			</Button>
		</svelte:fragment>
	</DrawerContent>
</Drawer>
