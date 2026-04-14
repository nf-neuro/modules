include { REGISTRATION_ANTS as REGISTER_ATLAS_TEMPLATE  } from '../../../modules/nf-neuro/registration/ants/main'
include { REGISTRATION_ANTS as REGISTER_TEMPLATE_SUBJECT } from '../../../modules/nf-neuro/registration/ants/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as RESAMPLE_LABELS } from '../../../modules/nf-neuro/registration/antsapplytransforms/main'
include { SEGMENTATION_MAJORITYVOTE } from '../../../modules/nf-neuro/segmentation/majorityvote/main'
include { UTILS_OPTIONS } from '../utils_options/main'


workflow MAGETBRAIN {

    // MAGeT-Brain: Multiple Automatically Generated Templates Brain Segmentation
    //
    // Performs multi-atlas segmentation through combinatorial registration and
    // majority vote label fusion:
    //   1. Register every atlas to every template (atlas→template)
    //   2. Register every template to every subject (template→subject)
    //   3. Chain transforms to resample atlas labels into each subject space
    //      through every possible atlas→template→subject path
    //   4. Majority vote across all candidate labels per subject

    take:
        ch_atlases      // channel: [ val(meta), path(image) ]
                        //   meta.id = atlas identifier
        ch_labels       // channel: [ val(meta), path(label) ]
                        //   meta.id = atlas identifier, meta.label_tag = e.g. "_label_amygdala"
        ch_templates    // channel: [ val(meta), path(image) ]
                        //   meta.id = template identifier
        ch_subjects     // channel: [ val(meta), path(image) ]
                        //   meta.id = subject identifier
        options         // Map of options

    main:
        ch_versions = channel.empty()

        UTILS_OPTIONS("${moduleDir}/meta.yml", options, true)
        options = UTILS_OPTIONS.out.options.value

        // ** Step 1: Atlas-Template Registration **
        // Combine every atlas with every template, then register.
        // REGISTRATION_ANTS input: [meta, fixed, moving, mask]
        // fixed=template, moving=atlas → forward transforms go atlas→template
        ch_atlas_template_pairs = ch_atlases
            .combine(ch_templates)
            .map { meta_atlas, atlas_img, meta_template, template_img ->
                def meta = [
                    id: "${meta_atlas.id}_to_${meta_template.id}",
                    moving_id: meta_atlas.id,
                    fixed_id: meta_template.id
                ]
                [meta, template_img, atlas_img, []]
            }

        REGISTER_ATLAS_TEMPLATE(ch_atlas_template_pairs)
        ch_versions = ch_versions.mix(REGISTER_ATLAS_TEMPLATE.out.versions.first())

        // ** Step 2: Template-Subject Registration **
        // Combine every template with every subject, then register.
        // fixed=subject, moving=template → forward transforms go template→subject
        ch_template_subject_pairs = ch_templates
            .combine(ch_subjects)
            .map { meta_template, template_img, meta_subject, subject_img ->
                def meta = [
                    id: "${meta_template.id}_to_${meta_subject.id}",
                    moving_id: meta_template.id,
                    fixed_id: meta_subject.id
                ]
                [meta, subject_img, template_img, []]
            }

        REGISTER_TEMPLATE_SUBJECT(ch_template_subject_pairs)
        ch_versions = ch_versions.mix(REGISTER_TEMPLATE_SUBJECT.out.versions.first())

        // ** Step 3: Chain Transforms & Resample Labels **
        // For every atlas→template→subject path, chain the two sets of
        // forward transforms and apply them to resample atlas labels into
        // subject space.
        //
        // forward_image_transform = [forward0_warp.nii.gz, forward1_affine.mat]
        // (glob-sorted alphabetically, i.e. [warp, affine])
        //
        // Transform ordering for antsApplyTransforms (applied right-to-left):
        //   ts_transforms + at_transforms = [ts_warp, ts_affine, at_warp, at_affine]
        //   → -t ts_warp -t ts_affine -t at_warp -t at_affine
        //   → applied: at_affine → at_warp → ts_affine → ts_warp
        //   → atlas → template → subject  ✓

        // Key atlas-template transforms by templateId for combining
        ch_at_transforms = REGISTER_ATLAS_TEMPLATE.out.forward_image_transform
            .map { meta, transforms -> [meta.fixed_id, meta.moving_id, transforms] }
            // [templateId, atlasId, [at_warp, at_affine]]

        // Key template-subject transforms by templateId for combining
        ch_ts_transforms = REGISTER_TEMPLATE_SUBJECT.out.forward_image_transform
            .map { meta, transforms -> [meta.moving_id, meta.fixed_id, transforms] }
            // [templateId, subjectId, [ts_warp, ts_affine]]

        // Combine on templateId: all atlas-template x template-subject pairs sharing a template
        ch_combined = ch_at_transforms
            .combine(ch_ts_transforms, by: 0)
            // [templateId, atlasId, [at_warp, at_affine], subjectId, [ts_warp, ts_affine]]

        // Key labels by atlasId
        ch_labels_keyed = ch_labels
            .map { meta, label -> [meta.id, meta.label_tag, label] }

        // Key subjects by subjectId
        ch_subjects_keyed = ch_subjects
            .map { meta, image -> [meta.id, image] }

        // Add labels (combine on atlasId)
        ch_with_labels = ch_combined
            .map { templateId, atlasId, at_xfm, subjectId, ts_xfm ->
                [atlasId, templateId, subjectId, at_xfm, ts_xfm]
            }
            .combine(ch_labels_keyed, by: 0)
            // [atlasId, templateId, subjectId, at_xfm, ts_xfm, label_tag, label_file]

        // Add subject images (combine on subjectId) and build ANTSAPPLYTRANSFORMS input
        ch_for_resample = ch_with_labels
            .map { atlasId, templateId, subjectId, at_xfm, ts_xfm, label_tag, label_file ->
                [subjectId, atlasId, templateId, at_xfm, ts_xfm, label_tag, label_file]
            }
            .combine(ch_subjects_keyed, by: 0)
            // [subjectId, atlasId, templateId, at_xfm, ts_xfm, label_tag, label_file, subject_image]
            .map { subjectId, atlasId, templateId, at_xfm, ts_xfm, label_tag, label_file, subject_image ->
                def meta = [
                    id: "${subjectId}${label_tag}_via_${atlasId}_${templateId}",
                    subject_id: subjectId,
                    label_tag: label_tag
                ]
                // Chain transforms: template→subject then atlas→template
                def chained_transforms = ts_xfm + at_xfm
                // ANTSAPPLYTRANSFORMS input: [meta, images, reference, transformations]
                [meta, label_file, subject_image, chained_transforms]
            }

        RESAMPLE_LABELS(ch_for_resample)
        ch_versions = ch_versions.mix(RESAMPLE_LABELS.out.versions.first())

        // ** Step 4: Group & Majority Vote **
        // Group resampled candidate labels by (subject_id, label_tag),
        // then select the most frequent label at each voxel.
        ch_grouped = RESAMPLE_LABELS.out.warped_image
            .map { meta, warped_label ->
                [meta.subject_id, meta.label_tag, warped_label]
            }
            .groupTuple(by: [0, 1])
            .map { subject_id, label_tag, labels ->
                [[id: "${subject_id}${label_tag}"], labels]
            }

        SEGMENTATION_MAJORITYVOTE(ch_grouped)
        ch_versions = ch_versions.mix(SEGMENTATION_MAJORITYVOTE.out.versions.first())

    emit:
        labels   = SEGMENTATION_MAJORITYVOTE.out.label  // channel: [ val(meta), path(label) ]
        versions = ch_versions                           // channel: [ versions.yml ]
}
